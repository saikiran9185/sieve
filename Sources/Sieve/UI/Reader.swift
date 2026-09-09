import SwiftUI
import PDFKit
import AppKit

/// Bridges SwiftUI to the live PDFView so the toolbar can drive it.
@MainActor
final class PDFController: ObservableObject {
    weak var view: PDFView?
    @Published var selectionText: String = ""
    @Published var pageLabel: String = ""
    @Published var pageCount: Int = 0
    @Published var currentPage: Int = 0
    @Published var searchMatches: [PDFSelection] = []
    @Published var searchIndex: Int = 0
    @Published var zoom: Double = 1

    /// Which paper the live view is showing, so its place can be filed under the right paper.
    var paperId: Int? = nil

    var hasSelection: Bool { !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func go(to pageIndex: Int) {
        guard let doc = view?.document, let page = doc.page(at: pageIndex) else { return }
        view?.go(to: PDFDestination(page: page, at: NSPoint(x: 0, y: page.bounds(for: .mediaBox).height)))
    }

    // MARK: Zoom that stays put

    /// Zoom is changed here rather than through `zoomIn(_:)` so the view never has
    /// `autoScales` switched back on behind our back — which is what threw away the zoom
    /// every time the pane beside the document changed size.
    func setZoom(_ factor: Double) {
        guard let v = view else { return }
        let clamped = min(max(factor, 0.25), 8)
        v.autoScales = false
        v.scaleFactor = clamped
        zoom = clamped
        rememberPlace()
    }

    func zoomStep(_ multiplier: Double) { setZoom((view?.scaleFactor ?? 1) * multiplier) }

    /// The one place `autoScales` is allowed to act: an explicit "fit the width" request.
    func fitWidth() {
        guard let v = view else { return }
        v.autoScales = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let v = self.view else { return }
            v.autoScales = false
            self.zoom = v.scaleFactor
            self.rememberPlace()
        }
    }

    // MARK: Where you were

    func currentPlace() -> ReadingPosition? {
        guard let v = view, let doc = v.document else { return nil }
        guard let dest = v.currentDestination, let page = dest.page else { return nil }
        return ReadingPosition(page: doc.index(for: page),
                               scale: v.scaleFactor,
                               offsetX: dest.point.x,
                               offsetY: dest.point.y)
    }

    func rememberPlace() {
        guard let id = paperId, let place = currentPlace() else { return }
        ReadingMemory.save(place, paper: id)
    }

    func restore(_ place: ReadingPosition) {
        guard let v = view, let doc = v.document else { return }
        v.autoScales = false
        if place.hasScale { v.scaleFactor = place.scale; zoom = place.scale }
        guard let page = doc.page(at: min(max(place.page, 0), max(doc.pageCount - 1, 0))) else { return }
        v.go(to: PDFDestination(page: page, at: NSPoint(x: place.offsetX, y: place.offsetY)))
    }

    /// Jumps to a stored highlight and flashes it so the eye finds it immediately.
    func reveal(_ e: Evidence) {
        guard let doc = view?.document, e.page >= 0, let page = doc.page(at: e.page) else { return }
        go(to: e.page)
        guard let rect = e.rects.first else { return }
        view?.go(to: rect.insetBy(dx: -30, dy: -60), on: page)
        flash(rect: e.rects.reduce(e.rects[0]) { $0.union($1) }, on: page)
    }

    private func flash(rect: CGRect, on page: PDFPage) {
        let a = PDFAnnotation(bounds: rect.insetBy(dx: -3, dy: -3), forType: .square, withProperties: nil)
        a.color = NSColor.systemBlue
        a.interiorColor = NSColor.systemBlue.withAlphaComponent(0.25)
        page.addAnnotation(a)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { page.removeAnnotation(a) }
    }

    func find(_ text: String) {
        guard let doc = view?.document, !text.isEmpty else { searchMatches = []; return }
        searchMatches = doc.findString(text, withOptions: [.caseInsensitive])
        searchIndex = 0
        showMatch()
    }

    func stepMatch(_ delta: Int) {
        guard !searchMatches.isEmpty else { return }
        searchIndex = (searchIndex + delta + searchMatches.count) % searchMatches.count
        showMatch()
    }

    private func showMatch() {
        guard searchMatches.indices.contains(searchIndex) else { return }
        let sel = searchMatches[searchIndex]
        sel.color = NSColor.systemYellow
        view?.setCurrentSelection(sel, animate: true)
        view?.scrollSelectionToVisible(nil)
    }

    /// Returns the current selection broken into per-line rectangles on a single page,
    /// which is what a highlight annotation needs to hug the text instead of boxing it.
    func selectionGeometry() -> (page: Int, rects: [CGRect], text: String)? {
        guard let view, let sel = view.currentSelection, let doc = view.document else { return nil }
        let text = sel.string ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var rects: [CGRect] = []
        var pageIndex = -1
        for line in sel.selectionsByLine() {
            guard let p = line.pages.first else { continue }
            let idx = doc.index(for: p)
            if pageIndex == -1 { pageIndex = idx }
            guard idx == pageIndex else { continue }   // keep a highlight on one page
            rects.append(line.bounds(for: p))
        }
        guard pageIndex >= 0, !rects.isEmpty else { return nil }
        return (pageIndex, rects, text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func clearSelection() {
        view?.setCurrentSelection(nil, animate: false)
        selectionText = ""
    }
}

// MARK: - The PDFView itself

struct PDFKitView: NSViewRepresentable {
    let url: URL
    let paperId: Int
    @ObservedObject var controller: PDFController
    let evidence: [Evidence]
    /// Reading mode: the page as the publisher set it, with none of your marks on it.
    var hideHighlights: Bool = false
    let onHighlightTapped: (Int) -> Void

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        // `autoScales` refits the document to the view every time the view is resized. With
        // panes that open, close and slide, that meant reading at 200% and losing it the
        // moment anything beside the document changed width — including the toolbar reflowing
        // when a selection appeared. The initial fit is done once, below, and then the scale
        // is ours.
        v.autoScales = false
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = NSColor.underPageBackgroundColor
        v.pageShadowsEnabled = true
        controller.view = v
        context.coordinator.attach(v, controller: controller, onTap: onHighlightTapped)
        context.coordinator.load(url: url, paperId: paperId, into: v, controller: controller)
        context.coordinator.redraw(evidence: hideHighlights ? [] : evidence, in: v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if context.coordinator.loadedURL != url {
            // Leaving a paper files the place you left it, before the next one loads over it.
            context.coordinator.rememberPlace(in: v, controller: controller)
            context.coordinator.load(url: url, paperId: paperId, into: v, controller: controller)
        }
        controller.paperId = paperId

        // Redrawing annotations must not move the page or change the zoom. Saving a highlight
        // was doing both, which meant every mark you made cost you your place on the page.
        let scale = v.scaleFactor
        let place = v.currentDestination
        context.coordinator.redraw(evidence: hideHighlights ? [] : evidence, in: v)
        if abs(v.scaleFactor - scale) > 0.0001 { v.scaleFactor = scale }
        if let place, let page = place.page {
            let here = v.currentDestination
            if here?.page != page || abs((here?.point.y ?? 0) - place.point.y) > 1 {
                v.go(to: PDFDestination(page: page, at: place.point))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        private weak var pdfView: PDFView?
        private var controller: PDFController?
        private var onTap: ((Int) -> Void)?
        private var drawn: [Int: PDFAnnotation] = [:]   // evidence id -> annotation
        private var signature: String = ""
        private(set) var loadedURL: URL?
        private var loadedPaperId: Int?

        func attach(_ v: PDFView, controller: PDFController, onTap: @escaping (Int) -> Void) {
            pdfView = v; self.controller = controller; self.onTap = onTap
            NotificationCenter.default.addObserver(
                self, selector: #selector(selectionChanged),
                name: .PDFViewSelectionChanged, object: v)
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged),
                name: .PDFViewPageChanged, object: v)
            NotificationCenter.default.addObserver(
                self, selector: #selector(scaleChanged),
                name: .PDFViewScaleChanged, object: v)
        }

        /// Opens a document and puts you back where you stopped reading it — same page, same
        /// zoom, same position down the page. A paper you have never opened is fitted to the
        /// width of the pane once and left alone after that.
        func load(url: URL, paperId: Int, into v: PDFView, controller: PDFController) {
            loadedURL = url
            loadedPaperId = paperId
            controller.paperId = paperId
            signature = ""
            drawn = [:]
            v.document = PDFDocument(url: url)
            controller.pageCount = v.document?.pageCount ?? 0

            let saved = ReadingMemory.position(paper: paperId)
            if let saved, saved.hasScale {
                // A layout pass has to happen before a destination means anything.
                DispatchQueue.main.async { controller.restore(saved) }
            } else {
                v.autoScales = true
                DispatchQueue.main.async {
                    v.autoScales = false
                    controller.zoom = v.scaleFactor
                    if let saved { controller.restore(ReadingPosition(page: saved.page,
                                                                      scale: v.scaleFactor,
                                                                      offsetX: saved.offsetX,
                                                                      offsetY: saved.offsetY)) }
                }
            }
        }

        func rememberPlace(in v: PDFView, controller: PDFController) {
            guard let id = loadedPaperId, let doc = v.document,
                  let dest = v.currentDestination, let page = dest.page else { return }
            ReadingMemory.save(ReadingPosition(page: doc.index(for: page),
                                               scale: v.scaleFactor,
                                               offsetX: dest.point.x,
                                               offsetY: dest.point.y),
                               paper: id)
        }

        @objc private func scaleChanged() {
            guard let c = controller, let v = pdfView else { return }
            let s = v.scaleFactor
            Task { @MainActor in c.zoom = s }
        }

        @objc private func selectionChanged() {
            guard let c = controller, let v = pdfView else { return }
            let s = v.currentSelection?.string ?? ""
            Task { @MainActor in c.selectionText = s }
        }

        @objc private func pageChanged() {
            guard let c = controller, let v = pdfView, let doc = v.document, let p = v.currentPage else { return }
            let i = doc.index(for: p)
            Task { @MainActor in
                c.currentPage = i
                c.pageLabel = "\(i + 1) / \(doc.pageCount)"
                // Filed as you read, not only on the way out, so a crash or a force quit
                // still costs you nothing.
                self.rememberPlace(in: v, controller: c)
            }
        }

        /// Re-renders stored highlights as PDF annotations. Cheap because it only
        /// redraws when the set of highlights actually changed.
        func redraw(evidence: [Evidence], in v: PDFView) {
            let sig = evidence.map { "\($0.id):\($0.colorHex):\($0.rects.count)" }.joined(separator: "|")
            guard sig != signature, let doc = v.document else { return }
            signature = sig

            for (_, a) in drawn { a.page?.removeAnnotation(a) }
            drawn = [:]

            for e in evidence where e.page >= 0 && e.page < doc.pageCount {
                guard let page = doc.page(at: e.page), !e.rects.isEmpty else { continue }
                let bounds = e.rects.reduce(e.rects[0]) { $0.union($1) }
                let a = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                a.color = NSColor(Color(hex: e.colorHex)).withAlphaComponent(0.42)
                a.contents = e.note.isEmpty ? e.quote : e.note
                // Per-line quad points make the highlight follow the text, not a bounding box.
                a.quadrilateralPoints = e.rects.flatMap { r -> [NSValue] in
                    let o = CGPoint(x: r.minX - bounds.minX, y: r.minY - bounds.minY)
                    return [NSValue(point: NSPoint(x: o.x, y: o.y + r.height)),
                            NSValue(point: NSPoint(x: o.x + r.width, y: o.y + r.height)),
                            NSValue(point: NSPoint(x: o.x, y: o.y)),
                            NSValue(point: NSPoint(x: o.x + r.width, y: o.y))]
                }
                page.addAnnotation(a)
                drawn[e.id] = a
            }
        }

        nonisolated deinit { NotificationCenter.default.removeObserver(self) }
    }
}

// MARK: - Reader screen

struct ReaderScreen: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var downloader: Downloader
    @EnvironmentObject var engine: SearchEngine
    @StateObject private var controller = PDFController()

    @State private var activeTagId: Int? = nil
    @State private var findText = ""
    @State private var noteTarget: Evidence? = nil
    @State private var keyMonitor: Any? = nil
    @State private var railFilter: RailFilter = .included
    @State private var railSearch = ""
    @State private var stance: Stance = .evidence
    @State private var showThought = false
    @AppStorage("sieve.readerRailWidth") private var railWidth: Double = 250
    @AppStorage("sieve.readerInspectorWidth") private var inspectorWidth: Double = 340
    @AppStorage("sieve.showPaperList") private var showPaperList: Bool = true
    @AppStorage("sieve.showInspector") private var showInspector: Bool = true
    @State private var showShortcuts = false
    @State private var stripHovered = false

    /// The reader's own view of the library. "Included" is the default because the point
    /// of this screen is the papers that made it into the review.
    enum RailFilter: String, CaseIterable, Identifiable {
        case included = "Included", withPDF = "Has PDF", starred = "Starred", all = "All"
        var id: String { rawValue }
    }

    private var paper: Paper? {
        if let id = nav.readingPaperId { return store.paper(id) }
        return store.included.first ?? store.papers.first { $0.hasPDF }
    }

    /// In reading mode the panels either side are gone, not merely narrow.
    private var railVisible: Bool { showPaperList && !nav.focusMode }
    private var inspectorVisible: Bool { showInspector && !nav.focusMode }

    var body: some View {
        HStack(spacing: 0) {
            if railVisible {
                paperRail.frame(width: railWidth)
                PaneDivider(width: $railWidth, range: 180...400)
            }
            mainReader.frame(maxWidth: .infinity)
            if inspectorVisible {
                PaneDivider(width: $inspectorWidth, range: 260...540, sizesTrailingPane: true)
                InspectorPanel(paper: paper, controller: controller, focusEvidenceId: $noteTarget)
                    .frame(width: inspectorWidth)
            }
        }
        .background(D.canvas)
        .onAppear { installKeyMonitor(); ensureActiveTag() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            controller.rememberPlace()
        }
        .sheet(isPresented: $showShortcuts) { ShortcutSheet { showShortcuts = false } }
        .onChange(of: store.tags.count) { _, _ in ensureActiveTag() }
        // Switching papers files the place in the one you are leaving.
        .onChange(of: nav.readingPaperId) { _, _ in controller.clearSelection() }
    }

    private func ensureActiveTag() {
        if activeTagId == nil || !store.tags.contains(where: { $0.id == activeTagId }) {
            activeTagId = store.categoryTags.first?.id
        }
    }

    // MARK: Left rail — the papers you can read

    private var paperRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "Papers")
                Spacer()
                Button { showPaperList = false } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, D.s3).padding(.top, D.s3).padding(.bottom, 6)

            HStack(spacing: 5) {
                Picker("", selection: $railFilter) {
                    ForEach(RailFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                Text("\(readable.count)")
                    .font(D.small.monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, D.s2)

            SearchField(placeholder: "Find a paper", text: $railSearch)
                .padding(.horizontal, D.s2).padding(.vertical, 6)

            Divider()
            if readable.isEmpty {
                VStack(spacing: 6) {
                    Text(railFilter == .included ? "No papers included yet" : "Nothing here")
                        .font(D.small).foregroundStyle(.secondary)
                    if railFilter == .included {
                        Button("Show all papers") { railFilter = .all }.font(D.small)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(D.s3)
            } else {
                List {
                    ForEach(readable) { p in
                        Button { nav.readingPaperId = p.id; controller.clearSelection() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title).font(D.small.weight(.medium)).lineLimit(2)
                                Text("\(p.authorLine) · \(p.year.map(String.init) ?? "n.d.")")
                                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                                HStack(spacing: 4) {
                                    // The stage sits right on the row, so "is this one in or
                                    // out?" is answered without leaving the reader.
                                    StageBadge(stage: p.stage)
                                    let n = store.evidenceCount(forPaper: p.id)
                                    if n > 0 { Chip(text: "\(n)", color: Palette.amber, icon: "highlighter") }
                                    Spacer()
                                    if !p.hasPDF {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(p.id == paper?.id ? Palette.accent.opacity(0.14) : Color.clear)
                        .contextMenu {
                            if p.stage == .included {
                                Button("Remove from review") { store.setStage(p.id, .eligibility, reason: "") }
                            } else {
                                Button("Include in review") { store.setStage(p.id, .included, reason: "") }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var readable: [Paper] {
        let base: [Paper]
        switch railFilter {
        case .included: base = store.papers.filter { $0.stage == .included }
        case .withPDF:  base = store.papers.filter { $0.hasPDF }
        case .starred:  base = store.papers.filter { $0.starred }
        case .all:      base = store.papers.filter { !$0.stage.isExcluded }
        }
        let filtered = railSearch.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(railSearch)
            || $0.authorLine.localizedCaseInsensitiveContains(railSearch)
        }
        return filtered.sorted { ($0.hasPDF ? 0 : 1, $0.title) < ($1.hasPDF ? 0 : 1, $1.title) }
    }

    // MARK: Centre — the document

    private var mainReader: some View {
        VStack(spacing: 0) {
            if !nav.focusMode {
                readerToolbar
                highlightPalette
                Divider()
            }
            Group {
                if let p = paper, p.hasPDF {
                    PDFKitView(url: URL(fileURLWithPath: p.pdfPath),
                               paperId: p.id,
                               controller: controller,
                               evidence: store.evidence(forPaper: p.id),
                               hideHighlights: nav.hideHighlights,
                               onHighlightTapped: { _ in })
                } else if let p = paper {
                    missingPDF(p)
                } else {
                    EmptyState(icon: "doc.text",
                               title: "Nothing to read yet",
                               message: "Add papers from Find papers, or drop a PDF anywhere in this window.")
                }
            }
        }
        .frame(minWidth: 420)
        // Everything below is drawn over the document rather than above it in a stack.
        // A control that appears must never resize the page — that resize is what used to
        // throw away the zoom and the scroll position at the exact moment you marked something.
        .overlay(alignment: .top) { if nav.focusMode { focusStrip } }
        .overlay(alignment: .top) { if controller.hasSelection { floatingPalette } }
        .overlay(alignment: .bottomTrailing) { noteComposer }
        .overlay(alignment: .bottomLeading) { if nav.hideHighlights { hiddenNotice } }
    }

    /// The only chrome reading mode keeps: a thin bar that says where you are and how to get
    /// the workspace back. It fades to almost nothing until the pointer is near it.
    private var focusStrip: some View {
        HStack(spacing: D.s2) {
            Button { nav.focusMode = false } label: {
                Label("Exit reading mode", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(D.small)
            }
            .buttonStyle(.plain)
            .help("Bring the panels back (⌃⌘F)")

            Divider().frame(height: 12)
            UndoRedoButtons(history: store.history, store: store)
            Divider().frame(height: 12)

            Button { controller.zoomStep(1 / 1.15) } label: {
                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
            }
            .buttonStyle(.plain).help("Zoom out (⌘−)")
            Text("\(Int(controller.zoom * 100))%")
                .font(D.small.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 38)
            Button { controller.zoomStep(1.15) } label: {
                Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
            }
            .buttonStyle(.plain).help("Zoom in (⌘+)")
            Button { controller.fitWidth() } label: {
                Image(systemName: "arrow.left.and.right").accessibilityHidden(true)
            }
            .buttonStyle(.plain).help("Fit the width (⌘0)")

            Divider().frame(height: 12)
            Button { nav.hideHighlights.toggle() } label: {
                Image(systemName: nav.hideHighlights ? "eye.slash" : "eye").accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .help(nav.hideHighlights ? "Show your highlights (⌃⌘H)" : "Hide your highlights (⌃⌘H)")

            if !controller.pageLabel.isEmpty {
                Text(controller.pageLabel).font(D.small.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, D.s3).padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(D.hairline, lineWidth: 0.5))
        .padding(.top, D.s2)
        // Faint until you reach for it. A control bar floating over the first lines of a page
        // is worse than no control bar, and the point of this mode is the page.
        .opacity(stripHovered ? 1 : 0.28)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { stripHovered = hovering }
        }
    }

    /// The colours, over the page, only while there is something selected. In reading mode
    /// this is the whole toolbar; outside it, it saves the trip up to the strip.
    private var floatingPalette: some View {
        HStack(spacing: 5) {
            Text("Mark as").font(D.small).foregroundStyle(.secondary)
            ForEach(store.categoryTags) { tag in
                Button { activeTagId = tag.id; highlight(with: tag) } label: {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(tag.color).frame(width: 10, height: 10)
                        Text(tag.name).font(D.small)
                        if !tag.shortcut.isEmpty {
                            Text(tag.shortcut).font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(tag.color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(tag.detail.isEmpty ? "Mark the selection as \(tag.name)" : "\(tag.name) — \(tag.detail)")
            }
            Divider().frame(height: 12)
            Text(stance.label).font(.system(size: 10)).foregroundStyle(stance.color)
        }
        .padding(.horizontal, D.s3).padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(D.hairline, lineWidth: 0.5))
        .padding(.top, nav.focusMode ? 42 : D.s2)
        .transition(.opacity)
    }

    private var hiddenNotice: some View {
        Button { nav.hideHighlights = false } label: {
            Label("Your highlights are hidden", systemImage: "eye.slash").font(D.small)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, D.s3).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .padding(D.s3)
        .help("Show them again (⌃⌘H)")
    }

    /// The note box for the passage you just marked, over the page you marked it on.
    ///
    /// Writing the note used to mean finding the highlight at the bottom of a list that grows
    /// all day. It arrives here instead, already knowing which passage it belongs to, and it
    /// does not move the document to appear.
    @ViewBuilder
    private var noteComposer: some View {
        if let e = noteTarget {
            HighlightNoteBox(evidence: e,
                             onClose: { noteTarget = nil },
                             onReveal: { controller.reveal(e) })
                .frame(width: 340)
                .padding(D.s3)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func missingPDF(_ p: Paper) -> some View {
        VStack(spacing: D.s4) {
            EmptyState(icon: "doc.badge.plus",
                       title: "No PDF attached",
                       message: "\(p.title)\n\nSieve can only fetch legally free copies. If this paper is paywalled, download it through your library and drop it into this window.")
            HStack(spacing: D.s2) {
                Button {
                    Task { await downloader.fetch(paper: p, store: store, email: engine.contactEmail) }
                } label: {
                    if downloader.active[p.id] != nil {
                        HStack { ProgressView().controlSize(.small); Text(downloader.active[p.id] ?? "") }
                    } else { Label("Look for a free PDF", systemImage: "arrow.down.circle") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(downloader.active[p.id] != nil)

                if !p.url.isEmpty {
                    Button("Open publisher page") {
                        SafeLink.open(SafeLink.forPaper(url: p.url, doi: p.doi)
                                      ?? URL(fileURLWithPath: "/"))
                    }
                }
                Button("Attach a PDF…") { attachPDF(to: p) }
            }
            .padding(.bottom, D.s6)
        }
    }

    private func attachPDF(to p: Paper) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose the PDF for “\(p.title)”"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let project = store.project else { return }
        let dir = Library.pdfDir(id: project.id, name: project.name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(Downloader.filename(for: p))
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            store.setPDFPath(p.id, dest.path)
            store.flash("PDF attached")
        } catch { store.flash("Could not copy that file") }
    }

    private var readerToolbar: some View {
        Toolbar {
            if !showPaperList {
                Button { showPaperList = true } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(paper?.title ?? "No paper").font(D.body.weight(.medium)).lineLimit(1)
                Text(paper.map { "\($0.authorLine) · \($0.year.map(String.init) ?? "n.d.")" } ?? "")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            SearchField(placeholder: "Find in document", text: $findText) { controller.find(findText) }
                .frame(width: 190)
            if !controller.searchMatches.isEmpty {
                Text("\(controller.searchIndex + 1)/\(controller.searchMatches.count)")
                    .font(D.small.monospacedDigit()).foregroundStyle(.secondary)
                Button { controller.stepMatch(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain)
                Button { controller.stepMatch(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain)
            }
            Divider().frame(height: 16)
            UndoRedoButtons(history: store.history, store: store)
            Divider().frame(height: 16)
            Button { controller.zoomStep(1 / 1.15) } label: {
                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
            }
            .buttonStyle(.plain).help("Zoom out (⌘−)")
            Button { controller.fitWidth() } label: {
                Text("\(Int(controller.zoom * 100))%")
                    .font(D.small.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .buttonStyle(.plain).help("Fit the width (⌘0)")
            Button { controller.zoomStep(1.15) } label: {
                Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
            }
            .buttonStyle(.plain).help("Zoom in (⌘+)")
            if !controller.pageLabel.isEmpty {
                Text(controller.pageLabel).font(D.small.monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider().frame(height: 16)
            Button { nav.hideHighlights.toggle() } label: {
                Image(systemName: nav.hideHighlights ? "eye.slash" : "eye").accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(nav.hideHighlights ? Palette.accent : Color.primary)
            .help(nav.hideHighlights ? "Show your highlights (⌃⌘H)" : "Hide your highlights (⌃⌘H)")
            Button { nav.focusMode = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .help("Reading mode — hide every panel and give the page the window (⌃⌘F)")
            Button { showInspector.toggle() } label: {
                Image(systemName: "sidebar.right").accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showInspector ? Color.primary : Color.secondary)
            .help(showInspector ? "Hide the highlights panel" : "Show the highlights panel")
        }
    }

    // MARK: The colour palette — the heart of the tool

    private var highlightPalette: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The stance switch sits above the colours because it changes what the colour
            // MEANS: the same passage marked as interpretation is your thinking, not the
            // source's words, and the app must never let those blur together.
            HStack(spacing: D.s2) {
                Text("Recording").font(D.small).foregroundStyle(.secondary)
                ForEach(Stance.allCases) { st in
                    Button { stance = st } label: {
                        HStack(spacing: 4) {
                            Image(systemName: st.icon).font(.system(size: 9))
                            Text(st.label).font(D.small)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(stance == st ? st.color.opacity(0.18) : Color.secondary.opacity(0.06))
                        .foregroundStyle(stance == st ? st.color : .secondary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(stance == st ? st.color : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(st.blurb)
                }
                Text(stance.blurb).font(.system(size: 10)).foregroundStyle(.tertiary)
                    .lineLimit(1).frame(width: 220, alignment: .leading)
                Spacer()
                Button { showShortcuts = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "keyboard").font(.system(size: 9))
                        Text("? keys").font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Keyboard shortcuts")
                Button { showThought = true } label: {
                    Label("Add a thought", systemImage: "plus.bubble")
                        .font(D.small)
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
                .help("Record an interpretation or a question that isn't tied to a passage")
            }

            colourStrip
        }
        .padding(.horizontal, D.s4).padding(.vertical, D.s2)
        .frame(height: 66)
        .background(D.surface)
        .sheet(isPresented: $showThought) {
            if let p = paper {
                ThoughtSheet(paper: p, page: controller.currentPage) { showThought = false }
            }
        }
    }

    private var colourStrip: some View {
        HStack(spacing: D.s2) {
            Text("as").font(D.small).foregroundStyle(.secondary)
            ForEach(store.categoryTags) { tag in
                Button { activeTagId = tag.id; highlight(with: tag) } label: {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tag.color)
                            .frame(width: 12, height: 12)
                        Text(tag.name).font(D.small)
                        if !tag.shortcut.isEmpty {
                            Text(tag.shortcut).font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(activeTagId == tag.id ? tag.color.opacity(0.18) : Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(activeTagId == tag.id ? tag.color : .clear, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .help(tag.detail.isEmpty ? "Highlight the selection as \(tag.name)"
                                         : "\(tag.name) — \(tag.detail)")
            }
            Spacer()
            // Fixed width and one line, always. This label used to grow and shrink with the
            // selection, changing the height of the bar and so the height of the document
            // view under it — which refitted the page and lost the zoom every time you
            // selected a passage to mark.
            Text(controller.hasSelection
                 ? "\(controller.selectionText.split(separator: " ").count) words selected"
                 : "Select text, then click a colour or press its number")
                .font(D.small)
                .foregroundStyle(controller.hasSelection ? Palette.accent : Color.secondary.opacity(0.7))
                .lineLimit(1)
                .frame(width: 260, alignment: .trailing)
        }
        .frame(height: 22)
    }

    /// Turns the live text selection into a stored piece of evidence.
    private func highlight(with tag: Tag) {
        guard let p = paper else { return }
        guard let geo = controller.selectionGeometry() else {
            store.flash("Select some text in the PDF first")
            return
        }
        // The place is filed before the write, so even if a redraw were to move the page the
        // reader can be put back exactly where the passage was.
        let place = controller.currentPlace()
        let id = store.addEvidence(paperId: p.id, page: geo.page, quote: geo.text,
                                   color: tag.colorHex, tagIds: [tag.id], rects: geo.rects,
                                   kind: kindFor(tag), stance: stance)
        controller.clearSelection()
        if let place { controller.restore(place) }
        store.flash("Saved as \(stance.label.lowercased()) · \(tag.name) · p.\(geo.page + 1) — ⌘Z undoes it")
        // The note box opens on the passage you just marked, prefilled with nothing but
        // already attached to the right highlight.
        if let e = store.evidence(id) {
            withAnimation(.easeOut(duration: 0.15)) { noteTarget = e }
        }
    }

    /// The tag's own name is the best available signal for what kind of thing a passage is,
    /// so a tag called "Finding" records findings without the user setting anything twice.
    private func kindFor(_ tag: Tag) -> EvidenceKind {
        switch tag.name.lowercased() {
        case let n where n.contains("finding"): return .finding
        case let n where n.contains("stat") || n.contains("number"): return .statistic
        case let n where n.contains("definition"): return .definition
        case let n where n.contains("observ"): return .observation
        case let n where n.contains("claim"): return .claim
        default: return stance == .evidence ? .quote : .claim
        }
    }

    /// Number keys 1–9 pick a colour and highlight in one keystroke — the thing you do
    /// hundreds of times per paper has to cost one key, not a menu. The rest keep the whole
    /// reading loop on the left hand, so the right can stay on the trackpad selecting text.
    ///
    ///   1–9  highlight the selection in that colour
    ///   [ ]  previous / next paper       E I Q  switch what you are recording
    ///   ?    the shortcut list
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard nav.section == .reader, !event.modifierFlags.contains(.command) else { return event }
            // A note or a search field must always win the keystroke.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return event }

            if chars == "?" { showShortcuts.toggle(); return nil }

            // Escape gives the page back: it closes the note box, then the selection, then
            // reading mode. One key, always the way out.
            if event.keyCode == 53 {
                if noteTarget != nil { noteTarget = nil; return nil }
                if controller.hasSelection { controller.clearSelection(); return nil }
                if nav.focusMode { nav.focusMode = false; return nil }
                return event
            }

            switch chars.lowercased() {
            case "f": nav.focusMode.toggle(); return nil
            case "h": nav.hideHighlights.toggle(); return nil
            case "-": controller.zoomStep(1 / 1.15); return nil
            case "=", "+": controller.zoomStep(1.15); return nil
            case "0": controller.fitWidth(); return nil
            case "n":
                // Write a note on the most recent highlight without hunting for it.
                if let p = paper, let last = store.evidenceNewestFirst(forPaper: p.id).first {
                    noteTarget = last
                }
                return nil
            default: break
            }

            // Move through the reading list without leaving the keyboard.
            if chars == "[" || chars == "]" {
                let list = readable
                guard let here = list.firstIndex(where: { $0.id == paper?.id }) else { return nil }
                let next = chars == "]" ? here + 1 : here - 1
                if list.indices.contains(next) {
                    nav.readingPaperId = list[next].id
                    controller.clearSelection()
                }
                return nil
            }

            // Switch what the next highlight records, without reaching for the mouse.
            switch chars.lowercased() {
            case "e": stance = .evidence; return nil
            case "i": stance = .interpretation; return nil
            case "q": stance = .question; return nil
            default: break
            }

            guard chars.count == 1, let digit = Int(chars), (1...9).contains(digit) else { return event }
            // Only steal a digit when there is actually a selection to act on.
            guard controller.selectionGeometry() != nil else { return event }
            if let tag = store.categoryTags.first(where: { $0.shortcut == String(digit) }) {
                highlight(with: tag)
                return nil
            }
            return event
        }
    }
}

/// Records an interpretation or a question that isn't anchored to a passage. Your own
/// thinking deserves a first-class place in the corpus — but stored as thinking, never as
/// something the source said.
struct ThoughtSheet: View {
    let paper: Paper
    let page: Int
    var done: () -> Void
    @EnvironmentObject var store: Store
    @State private var stance: Stance = .interpretation
    @State private var text = ""
    @State private var tagId: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Text("Add a thought").font(D.title)
            Text("About “\(paper.title)”").font(D.small).foregroundStyle(.secondary).lineLimit(1)

            HStack(spacing: 6) {
                ForEach([Stance.interpretation, .question, .evidence]) { st in
                    Button { stance = st } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: st.icon).font(.system(size: 10))
                                Text(st.label).font(D.body.weight(.medium))
                            }
                            Text(st.blurb).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .padding(D.s2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(stance == st ? st.color.opacity(0.12) : Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(stance == st ? st.color : .clear, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                }
            }

            StableTextEditor(text: $text, placeholder: "What are you thinking?")
                .frame(height: 110)
                .background(D.surface).clipShape(RoundedRectangle(cornerRadius: D.radius))
                .hairlineBorder()

            HStack(spacing: 5) {
                Text("Category").font(D.small).foregroundStyle(.secondary)
                ForEach(store.tags.filter { $0.tagKind == .type }) { t in
                    Button { tagId = t.id } label: {
                        Chip(text: t.name, color: t.color, filled: tagId == t.id)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("Filed against page \(page + 1)").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.addEvidence(paperId: paper.id, page: page, quote: text,
                                      color: tagId.flatMap { store.tag($0)?.colorHex } ?? stance.color.hexString,
                                      tagIds: tagId.map { [$0] } ?? [], rects: [],
                                      kind: stance == .question ? .claim : .claim, stance: stance)
                    store.flash("\(stance.label) recorded")
                    done()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(D.s5).frame(width: 560)
    }
}
