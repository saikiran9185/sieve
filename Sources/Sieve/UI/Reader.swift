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

    var hasSelection: Bool { !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func go(to pageIndex: Int) {
        guard let doc = view?.document, let page = doc.page(at: pageIndex) else { return }
        view?.go(to: PDFDestination(page: page, at: NSPoint(x: 0, y: page.bounds(for: .mediaBox).height)))
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
    @ObservedObject var controller: PDFController
    let evidence: [Evidence]
    let onHighlightTapped: (Int) -> Void

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = NSColor.underPageBackgroundColor
        v.pageShadowsEnabled = true
        v.document = PDFDocument(url: url)
        controller.view = v
        controller.pageCount = v.document?.pageCount ?? 0
        context.coordinator.attach(v, controller: controller, onTap: onHighlightTapped)
        context.coordinator.redraw(evidence: evidence, in: v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url {
            v.document = PDFDocument(url: url)
            controller.pageCount = v.document?.pageCount ?? 0
        }
        context.coordinator.redraw(evidence: evidence, in: v)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private weak var pdfView: PDFView?
        private var controller: PDFController?
        private var onTap: ((Int) -> Void)?
        private var drawn: [Int: PDFAnnotation] = [:]   // evidence id -> annotation
        private var signature: String = ""

        func attach(_ v: PDFView, controller: PDFController, onTap: @escaping (Int) -> Void) {
            pdfView = v; self.controller = controller; self.onTap = onTap
            NotificationCenter.default.addObserver(
                self, selector: #selector(selectionChanged),
                name: .PDFViewSelectionChanged, object: v)
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged),
                name: .PDFViewPageChanged, object: v)
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

        deinit { NotificationCenter.default.removeObserver(self) }
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
    @State private var showNoteFor: Evidence? = nil
    @State private var keyMonitor: Any? = nil
    @State private var showPaperList = true
    @State private var railFilter: RailFilter = .included
    @State private var railSearch = ""
    @State private var stance: Stance = .evidence
    @State private var showThought = false
    @AppStorage("sieve.readerRailWidth") private var railWidth: Double = 250
    @AppStorage("sieve.readerInspectorWidth") private var inspectorWidth: Double = 340

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

    var body: some View {
        HStack(spacing: 0) {
            if showPaperList {
                paperRail.frame(width: railWidth)
                PaneDivider(width: $railWidth, range: 180...400)
            }
            mainReader.frame(maxWidth: .infinity)
            PaneDivider(width: $inspectorWidth, range: 260...540, sizesTrailingPane: true)
            InspectorPanel(paper: paper, controller: controller).frame(width: inspectorWidth)
        }
        .background(D.canvas)
        .onAppear { installKeyMonitor() }
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }
        .onChange(of: store.tags.count) { _, _ in ensureActiveTag() }
        .onAppear { ensureActiveTag() }
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
                                    let n = store.evidence(forPaper: p.id).count
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
            readerToolbar
            highlightPalette
            Divider()
            Group {
                if let p = paper, p.hasPDF {
                    PDFKitView(url: URL(fileURLWithPath: p.pdfPath),
                               controller: controller,
                               evidence: store.evidence(forPaper: p.id),
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
        let dest = Library.pdfDir.appendingPathComponent(Downloader.filename(for: p))
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
            Button { controller.view?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }.buttonStyle(.plain)
            Button { controller.view?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(.plain)
            if !controller.pageLabel.isEmpty {
                Text(controller.pageLabel).font(D.small.monospacedDigit()).foregroundStyle(.secondary)
            }
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
                Spacer()
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
            if controller.hasSelection {
                Text("\(controller.selectionText.split(separator: " ").count) words selected")
                    .font(D.small).foregroundStyle(Palette.accent)
            } else {
                Text("Select text, then click a colour or press its number")
                    .font(D.small).foregroundStyle(.tertiary)
            }
        }
    }

    /// Turns the live text selection into a stored piece of evidence.
    private func highlight(with tag: Tag) {
        guard let p = paper else { return }
        guard let geo = controller.selectionGeometry() else {
            store.flash("Select some text in the PDF first")
            return
        }
        let id = store.addEvidence(paperId: p.id, page: geo.page, quote: geo.text,
                                   color: tag.colorHex, tagIds: [tag.id], rects: geo.rects,
                                   kind: kindFor(tag), stance: stance)
        controller.clearSelection()
        store.flash("Saved as \(stance.label.lowercased()) · \(tag.name) · p.\(geo.page + 1)")
        if let e = store.evidence.first(where: { $0.id == id }) { showNoteFor = e }
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
    /// hundreds of times per paper has to cost one key, not a menu.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard nav.section == .reader,
                  !event.modifierFlags.contains(.command),
                  let chars = event.charactersIgnoringModifiers, chars.count == 1,
                  let digit = Int(chars), (1...9).contains(digit) else { return event }
            // Only steal the key when there's actually a selection to act on.
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

            TextEditor(text: $text)
                .font(D.body).frame(height: 110).padding(4)
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
