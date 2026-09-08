import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var engine: SearchEngine
    @State private var dropTargeted = false
    @State private var importing: (done: Int, total: Int)? = nil
    @AppStorage("sieve.sidebarWidth") private var sidebarWidth: Double = 218
    @AppStorage("sieve.showSidebar") private var showSidebar: Bool = true

    var body: some View {
        // A plain HStack, not NavigationSplitView.
        //
        // On macOS 26 the split view renders its sidebar as a floating inset panel and lays
        // the detail column out edge-to-edge *underneath* it. Anything in the detail that
        // isn't a scroll view — a fixed-width pane, a header row — then sits below the
        // sidebar and gets clipped. Laying the two columns out here removes the overlay
        // entirely: the sidebar occupies real width and nothing is drawn under it.
        HStack(spacing: 0) {
            if showSidebar {
                Sidebar()
                    .frame(width: sidebarWidth)
                    .background(.bar)
                PaneDivider(width: $sidebarWidth, range: 190...330)
            }

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    MethodBar()
                    content
                }
                if let job = importing {
                    ToastView(text: "Importing \(job.done) of \(job.total)…")
                } else if let toast = store.toast {
                    ToastView(text: toast)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if !showSidebar {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { showSidebar = true }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(D.s2)
                    .help("Show the sidebar")
                }
            }
        }
        .background(D.canvas)
        // Drop a PDF anywhere in the window to add it to the review.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers); return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Palette.accent, lineWidth: 3)
                    .background(Palette.accent.opacity(0.06))
                    .overlay(
                        Label("Drop PDFs, a folder of them, or a .bib / .ris file",
                              systemImage: "arrow.down.doc")
                            .font(D.heading)
                            .padding(D.s4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: D.radiusL))
                    )
                    .allowsHitTesting(false)
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
        .sheet(isPresented: $nav.showNewProject) { NewProjectSheet() }
        .sheet(isPresented: $nav.showShortcuts) { ShortcutSheet { nav.showShortcuts = false } }
        .onChange(of: nav.requestImportPDF) { _, v in if v { nav.requestImportPDF = false; chooseFiles(pdf: true) } }
        .onChange(of: nav.requestImportBib) { _, v in if v { nav.requestImportBib = false; chooseFiles(pdf: false) } }
    }

    @ViewBuilder
    private var content: some View {
        switch nav.section {
        case .dashboard: DashboardView()
        case .search:    SearchView()
        case .library:   LibraryView()
        case .screening: ScreeningView()
        case .reader:    ReaderScreen()
        case .evidence:  EvidenceView()
        case .map:       MapView()
        case .matrix:    MatrixView()
        case .frames:    FramesView()
        case .prisma:    PrismaView()
        case .aiTrail:   AITrailView()
        case .method:    MethodView()
        case .tags:      TagsView()
        case .settings:  SettingsView()
        }
    }

    // MARK: - File intake

    private func chooseFiles(pdf: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if pdf { panel.allowedContentTypes = [.pdf] }
        else {
            panel.allowedContentTypes = [UTType(filenameExtension: "bib") ?? .plainText,
                                         UTType(filenameExtension: "ris") ?? .plainText,
                                         .plainText]
        }
        panel.message = pdf ? "Choose PDFs to add to this review"
                            : "Choose a BibTeX (.bib) or RIS (.ris) export"
        guard panel.runModal() == .OK else { return }
        ingest(panel.urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in ingest([url]) }
            }
        }
    }

    /// Expands a dropped folder into the files inside it, so a whole folder of PDFs — the
    /// obvious thing to drag from Finder — imports in one go.
    private func expand(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey]
                guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants])
                else { continue }
                for case let file as URL in walker
                where ["pdf", "bib", "ris", "bibtex"].contains(file.pathExtension.lowercased()) {
                    out.append(file)
                }
            } else {
                out.append(url)
            }
        }
        return out
    }

    private func ingest(_ dropped: [URL]) {
        Task { @MainActor in
            let urls = expand(dropped)
            guard !urls.isEmpty else {
                store.flash("Nothing to import — drop PDFs, a .bib/.ris file, or a folder of them")
                return
            }
            importing = (0, urls.count)
            defer { importing = nil }

            var pdfs = 0, refs = 0, already = 0
            var seen = Set<String>()
            for (i, url) in urls.enumerated() {
                importing = (i + 1, urls.count)
                // The same file can arrive twice in one drop when nested folders overlap.
                guard seen.insert(url.standardizedFileURL.path).inserted else { continue }

                let ext = url.pathExtension.lowercased()
                if ext == "pdf" {
                    let before = store.papers.count
                    if await Importers.importPDF(at: url, store: store) != nil {
                        if store.papers.count > before { pdfs += 1 } else { already += 1 }
                    }
                } else if ["bib", "ris", "txt", "bibtex"].contains(ext) {
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    for h in Importers.parseBibliography(text) {
                        if store.addPaper(from: h, query: "Imported from \(url.lastPathComponent)") != nil {
                            refs += 1
                        } else { already += 1 }
                    }
                    store.reloadPapers()
                }
            }
            var parts: [String] = []
            if pdfs > 0 { parts.append("\(pdfs) PDF\(pdfs == 1 ? "" : "s")") }
            if refs > 0 { parts.append("\(refs) reference\(refs == 1 ? "" : "s")") }
            let skipped = already > 0 ? " · \(already) already here, nothing duplicated" : ""
            store.flash(parts.isEmpty ? "Everything in that drop is already in this review."
                                      : "Added " + parts.joined(separator: " and ") + skipped)
        }
    }
}

// MARK: - Sidebar

/// The sidebar. When a method is active it becomes the method: the steps you chose, in the
/// order you chose them, with the one you're on marked. Everything else is still one click
/// away — a method guides the app, it never locks it.
struct Sidebar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @AppStorage("sieve.showAllSections") private var showAll = false

    private var method: Method? {
        guard let m = store.activeMethod, !m.blocks.isEmpty else { return nil }
        return m
    }

    /// Every step of the method, in order, one row each. Steps are deliberately NOT collapsed
    /// by screen: "Read", "Highlight" and "Code" all happen in the reader but they are three
    /// distinct moves, and a method that hides two of them stops being the method you wrote.
    private var methodSteps: [(index: Int, block: MethodBlock, section: Section)] {
        guard let m = method else { return [] }
        return m.blocks.enumerated().compactMap { i, block in
            guard let sec = Section(rawValue: block.section) else { return nil }
            return (i, block, sec)
        }
    }

    private var hiddenSections: [Section] {
        let shown = Set(methodSteps.map(\.section))
        return Section.allCases.filter { !shown.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectPicker
            Divider()
            List(selection: Binding(get: { nav.section }, set: { nav.section = $0 ?? .dashboard })) {
                if method != nil { methodList } else { plainList }
            }
            .listStyle(.sidebar)
            footer
        }
    }

    // MARK: Method-shaped

    @ViewBuilder
    private var methodList: some View {
        if let m = method {
            SwiftUI.Section {
                row(.dashboard)
                ForEach(methodSteps, id: \.index) { step in
                    stepRow(step, method: m)
                }
            } header: {
                HStack(spacing: 4) {
                    Text(m.name).font(D.label).tracking(0.6)
                    Spacer()
                    Button { nav.section = .method } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Change the method or its steps")
                }
            }

            SwiftUI.Section {
                DisclosureGroup(isExpanded: $showAll) {
                    ForEach(hiddenSections) { s in row(s) }
                } label: {
                    Text("Everything else").font(D.small).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A step is a button rather than a tagged list row: the same screen can appear at
    /// several steps, and duplicate selection tags would break the list.
    private func stepRow(_ step: (index: Int, block: MethodBlock, section: Section),
                         method m: Method) -> some View {
        let isCurrent = step.index == m.currentStep
        let isDone = step.index < m.currentStep
        let isViewing = nav.section == step.section
        return Button {
            nav.section = step.section
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Palette.accent
                              : (isDone ? Palette.emerald.opacity(0.85) : Color.secondary.opacity(0.16)))
                        .frame(width: 17, height: 17)
                    if isDone {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(step.index + 1)")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(isCurrent ? .white : .secondary)
                    }
                }
                Image(systemName: step.block.icon).font(.system(size: 11)).frame(width: 14)
                Text(step.block.label)
                    .font(isCurrent ? D.body.weight(.semibold) : D.body)
                Spacer()
                if let n = badge(step.section), n > 0 {
                    Text("\(n)").font(D.small.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isViewing ? Palette.accent.opacity(0.14)
                      : (isCurrent ? Palette.accent.opacity(0.06) : Color.clear))
        .help(step.block.blurb)
    }

    // MARK: No method chosen — everything, grouped

    @ViewBuilder
    private var plainList: some View {
        SwiftUI.Section {
            row(.dashboard); row(.search); row(.library)
        }
        SwiftUI.Section("Review") {
            row(.screening); row(.reader); row(.evidence); row(.map); row(.matrix); row(.prisma)
        }
        SwiftUI.Section("Setup") {
            row(.method); row(.tags); row(.settings)
        }
    }

    private func badge(_ s: Section) -> Int? {
        switch s {
        case .screening: return store.pendingScreening.count
        case .evidence: return store.evidence.count
        case .tags: return store.tags.count
        default: return nil
        }
    }

    private func row(_ s: Section) -> some View {
        Label {
            HStack {
                Text(s.title)
                if let n = badge(s), n > 0 {
                    Spacer()
                    Text("\(n)").font(D.small.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: s.icon)
        }
        .tag(s)
    }

    private var projectPicker: some View {
        HStack(spacing: 4) {
            projectMenu
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    UserDefaults.standard.set(false, forKey: "sieve.showSidebar")
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide the sidebar")
        }
        .padding(.horizontal, D.s3)
        .padding(.vertical, D.s3)
    }

    private var projectMenu: some View {
        Menu {
            ForEach(store.projects) { p in
                Button {
                    store.switchTo(p.id)
                } label: {
                    if p.id == store.currentProjectId { Label(p.name, systemImage: "checkmark") }
                    else { Text(p.name) }
                }
            }
            Divider()
            Button("New Review…") { nav.showNewProject = true }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.project?.name ?? "No review")
                    .font(D.heading).lineLimit(1)
                Text("\(store.papers.count) records · \(store.included.count) included")
                    .font(D.small).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.bottom, 4)
            if method == nil {
                Button { nav.section = .method } label: {
                    Label("Choose a method", systemImage: "slider.horizontal.3").font(D.small)
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
                .help("A method reorders this sidebar into the steps you actually work through")
            }
            Button {
                NSWorkspace.shared.open(Library.root)
            } label: {
                Label("Library folder", systemImage: "folder").font(D.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Text("Everything is stored locally in\n~/Documents/Sieve")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, D.s3)
        .padding(.bottom, D.s3)
    }
}

/// A thin strip across the top of the work area showing where you are in your method and
/// letting you move on. Only appears when a method is set, and only on the screens that
/// method actually uses.
struct MethodBar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator

    private var method: Method? {
        guard let m = store.activeMethod, !m.blocks.isEmpty else { return nil }
        return m
    }

    private var currentBlock: MethodBlock? {
        guard let m = method, m.blocks.indices.contains(m.currentStep) else { return nil }
        return m.blocks[m.currentStep]
    }

    private var onCurrentStep: Bool {
        currentBlock.map { Section(rawValue: $0.section) == nav.section } ?? false
    }

    var body: some View {
        if let m = method, let block = currentBlock {
            HStack(spacing: D.s3) {
                Button { nav.section = .method } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 10))
                        Text(m.name).font(D.small.weight(.medium))
                    }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)

                Divider().frame(height: 12)

                HStack(spacing: 5) {
                    Text("Step \(m.currentStep + 1) of \(m.blocks.count)")
                        .font(D.small.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: block.icon).font(.system(size: 10))
                        .foregroundStyle(onCurrentStep ? Palette.accent : .secondary)
                    Text(block.label)
                        .font(D.small.weight(.semibold))
                        .foregroundStyle(onCurrentStep ? Palette.accent : .primary)
                    Text("— \(block.blurb)").font(D.small).foregroundStyle(.tertiary).lineLimit(1)
                }

                Spacer()

                if !onCurrentStep {
                    Button {
                        if let s = Section(rawValue: block.section) { nav.section = s }
                    } label: { Label("Go to this step", systemImage: "arrow.right").font(D.small) }
                }

                if m.currentStep < m.blocks.count - 1 {
                    Button {
                        var q = m; q.currentStep += 1
                        store.saveMethod(q)
                        if let next = q.blocks[safe: q.currentStep],
                           let s = Section(rawValue: next.section) { nav.section = s }
                    } label: {
                        Label("Done — next step", systemImage: "checkmark").font(D.small)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button {
                        var q = m; q.currentStep = m.blocks.count
                        store.saveMethod(q)
                        store.flash("Method complete")
                    } label: { Label("Finish", systemImage: "flag.checkered").font(D.small) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            .padding(.horizontal, D.s4).padding(.vertical, 5)
            .background(onCurrentStep ? Palette.accent.opacity(0.07) : Color.secondary.opacity(0.05))
            .overlay(alignment: .bottom) { Rectangle().fill(D.hairline).frame(height: 0.5) }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Toast

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(D.body)
            .padding(.horizontal, D.s4).padding(.vertical, D.s2 + 2)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(D.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.bottom, D.s5)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: text)
    }
}

// MARK: - New project sheet

struct NewProjectSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var question = ""
    @State private var inclusion = ""
    @State private var exclusion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: D.s4) {
            Text("New review").font(D.title)
            Text("A review is a self-contained project: its own papers, tags, matrix and PRISMA counts.")
                .font(D.small).foregroundStyle(.secondary)

            field("Name", "e.g. Tactile interfaces for low-vision users", $name)
            field("Review question", "The one question this review answers", $question, lines: 2)

            HStack(alignment: .top, spacing: D.s3) {
                field("Include a paper if…", "peer-reviewed · 2015 or later · empirical", $inclusion, lines: 4)
                field("Exclude a paper if…", "not in English · no user study · opinion piece", $exclusion, lines: 4)
            }
            Text("Criteria can be edited any time in Settings. They're what the screening view checks against.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create review") {
                    let id = store.createProject(name: name.isEmpty ? "Untitled review" : name)
                    if var p = store.projects.first(where: { $0.id == id }) {
                        p.question = question; p.inclusionCriteria = inclusion; p.exclusionCriteria = exclusion
                        store.updateProject(p)
                    }
                    store.switchTo(id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(D.s5)
        .frame(width: 640)
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            TextField(placeholder, text: text, axis: lines > 1 ? .vertical : .horizontal)
                .textFieldStyle(.roundedBorder)
                .lineLimit(lines, reservesSpace: lines > 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
