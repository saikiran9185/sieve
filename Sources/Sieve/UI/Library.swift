import SwiftUI
import AppKit

/// The library: folders on the left, papers on the right, and a filter bar that can narrow
/// by stage, tag, author, year, SDG and open-access status at once.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var downloader: Downloader
    @EnvironmentObject var engine: SearchEngine
    @EnvironmentObject var enricher: Enricher

    @State private var filter = ""
    @State private var stageFilter: Set<Stage> = []
    @State private var onlyPDF = false
    @State private var onlyStarred = false
    @State private var onlyMissingPDF = false
    @State private var authorFilter = ""
    @State private var sdgFilter: Set<String> = []
    @State private var yearFrom = ""
    @State private var yearTo = ""
    @State private var selected: Set<Int> = []
    @State private var newFolderParent: Int?? = nil
    @State private var newFolderName = ""
    @State private var showFilters = false
    @AppStorage("sieve.libraryFolderWidth") private var folderWidth: Double = 220

    private var rows: [Paper] {
        let scope: [Paper]
        switch nav.librarySelection {
        case .all:        scope = store.papers
        case .unfiled:    scope = store.papers.filter { $0.folderId == nil }
        case .folder(let id): scope = store.papers(inFolder: id)
        }
        return scope.filter { p in
            (stageFilter.isEmpty || stageFilter.contains(p.stage))
            && (!onlyPDF || p.hasPDF)
            && (!onlyMissingPDF || !p.hasPDF)
            && (!onlyStarred || p.starred)
            && (sdgFilter.isEmpty || !Set(p.sdgs).isDisjoint(with: sdgFilter))
            && matchesAuthor(p)
            && matchesYear(p)
            && (filter.isEmpty
                || p.title.localizedCaseInsensitiveContains(filter)
                || p.authorLine.localizedCaseInsensitiveContains(filter)
                || p.venue.localizedCaseInsensitiveContains(filter)
                || p.abstract.localizedCaseInsensitiveContains(filter))
        }
    }

    private func matchesAuthor(_ p: Paper) -> Bool {
        let needle = authorFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return p.authors.contains { $0.lowercased().contains(needle) }
    }

    private func matchesYear(_ p: Paper) -> Bool {
        if let f = Int(yearFrom), (p.year ?? 0) < f { return false }
        if let t = Int(yearTo), (p.year ?? 9999) > t { return false }
        return true
    }

    private var activeFilterCount: Int {
        stageFilter.count + sdgFilter.count
            + (onlyPDF ? 1 : 0) + (onlyMissingPDF ? 1 : 0) + (onlyStarred ? 1 : 0)
            + (authorFilter.isEmpty ? 0 : 1)
            + (yearFrom.isEmpty ? 0 : 1) + (yearTo.isEmpty ? 0 : 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if showFilters { filterPanel; Divider() }
            if !selected.isEmpty { bulkBar }
            Divider()
            HStack(spacing: 0) {
                FolderTree(selected: $nav.librarySelection, moveTarget: moveSelected)
                    .frame(width: folderWidth)
                PaneDivider(width: $folderWidth, range: 170...360)
                paperList.frame(maxWidth: .infinity)
            }
        }
        .background(D.canvas)
    }

    private var toolbar: some View {
        Toolbar {
            SearchField(placeholder: "Filter by title, author, journal or abstract", text: $filter)
                .frame(maxWidth: 340)
            Button { withAnimation(.easeOut(duration: 0.15)) { showFilters.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle\(activeFilterCount > 0 ? ".fill" : "")")
                    Text("Filters")
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Palette.accent).foregroundStyle(.white).clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button {
                let n = store.markDuplicates()
                store.flash(n == 0 ? "No duplicates found" : "Marked \(n) duplicate record\(n == 1 ? "" : "s")")
            } label: { Label("Find duplicates", systemImage: "doc.on.doc") }
                .help("Collapse records that describe the same paper across databases")
            Button {
                Task {
                    let targets = rows.filter {
                        $0.abstract.isEmpty || $0.sdgs.isEmpty || $0.references.isEmpty
                    }
                    guard !targets.isEmpty else { store.flash("Nothing missing in this list"); return }
                    let r = await enricher.enrich(targets, store: store)
                    store.flash(Enricher.summary(r))
                }
            } label: {
                if enricher.running {
                    HStack(spacing: 5) { ProgressView().controlSize(.small); Text(enricher.progress) }
                } else {
                    Label("Fill in missing details", systemImage: "arrow.clockwise.circle")
                }
            }
            .disabled(enricher.running || rows.isEmpty)
            .help("Look up abstracts, SDGs, citation lists and dates for the papers in this list. Only empty fields are filled.")

            Button { nav.requestImportPDF = true } label: { Label("Add PDFs", systemImage: "plus") }
            Menu {
                Button("Export everything (one folder)…") { Exporters.exportEverything(store) }
                Divider()
                Button("Included papers as CSV") { Exporters.exportPapersCSV(store, only: .included) }
                Button("Whole library as CSV") { Exporters.exportPapersCSV(store, only: nil) }
                Button("BibTeX of included") { Exporters.exportBibTeX(store) }
                Button("Full review report as PDF") { Exporters.exportReportPDF(store) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .frame(width: 100)
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            HStack(alignment: .top, spacing: D.s5) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: "Stage")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 4)],
                              alignment: .leading, spacing: 4) {
                        ForEach(Stage.allCases) { s in
                            let n = store.papers.filter { $0.stage == s }.count
                            Button {
                                if stageFilter.contains(s) { stageFilter.remove(s) } else { stageFilter.insert(s) }
                            } label: {
                                Chip(text: "\(s.short) \(n)", color: s.color, filled: stageFilter.contains(s))
                            }
                            .buttonStyle(.plain).opacity(n == 0 ? 0.4 : 1)
                        }
                    }
                    .frame(width: 380)
                }

                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: "Year")
                    HStack(spacing: 4) {
                        TextField("from", text: $yearFrom).frame(width: 58)
                        Text("–").foregroundStyle(.secondary)
                        TextField("to", text: $yearTo).frame(width: 58)
                    }
                    .textFieldStyle(.roundedBorder).font(D.small)

                    SectionLabel(text: "Author")
                    TextField("surname", text: $authorFilter)
                        .textFieldStyle(.roundedBorder).frame(width: 140).font(D.small)
                }

                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: "Full text")
                    Toggle("Has a PDF", isOn: $onlyPDF).toggleStyle(.checkbox).font(D.small)
                    Toggle("Missing a PDF", isOn: $onlyMissingPDF).toggleStyle(.checkbox).font(D.small)
                    Toggle("Starred", isOn: $onlyStarred).toggleStyle(.checkbox).font(D.small)
                }

                if !allSDGs.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(text: "Sustainable Development Goal")
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(allSDGs, id: \.self) { g in
                                    Button {
                                        if sdgFilter.contains(g) { sdgFilter.remove(g) } else { sdgFilter.insert(g) }
                                    } label: {
                                        Chip(text: g, color: Palette.violet, filled: sdgFilter.contains(g))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 92)
                    }
                    .frame(width: 200)
                }
                Spacer()
            }
            if activeFilterCount > 0 {
                Button("Clear all filters") {
                    stageFilter = []; sdgFilter = []; onlyPDF = false; onlyMissingPDF = false
                    onlyStarred = false; authorFilter = ""; yearFrom = ""; yearTo = ""
                }
                .font(D.small)
            }
        }
        .padding(D.s4)
        .background(D.surface)
    }

    private var allSDGs: [String] { Array(Set(store.papers.flatMap(\.sdgs))).sorted() }

    private var bulkBar: some View {
        HStack(spacing: D.s2) {
            Text("\(selected.count) selected").font(D.small.weight(.medium))
            Spacer()
            Menu {
                Button("Review root (no folder)") { store.move(Array(selected), toFolder: nil); selected = [] }
                Divider()
                ForEach(store.folders) { f in
                    Button(folderPath(f)) { store.move(Array(selected), toFolder: f.id); selected = [] }
                }
            } label: { Label("Move to folder", systemImage: "folder") }
                .frame(width: 150)
            Button("Send to screening") { selected.forEach { store.setStage($0, .screening) }; selected = [] }
            Button("Mark included") { selected.forEach { store.setStage($0, .included) }; selected = [] }
            Button("Fetch free PDFs") {
                let ids = Array(selected); selected = []
                Task { @MainActor in
                    for id in ids {
                        guard let p = store.paper(id), !p.hasPDF else { continue }
                        await downloader.fetch(paper: p, store: store, email: engine.contactEmail)
                    }
                    store.flash("Finished fetching")
                }
            }
            Button("Delete", role: .destructive) { selected.forEach { store.deletePaper($0) }; selected = [] }
            Button("Clear") { selected = [] }
        }
        .padding(.horizontal, D.s4).padding(.vertical, D.s2)
        .background(Palette.accent.opacity(0.09))
    }

    private func folderPath(_ f: Folder) -> String {
        var parts = [f.name]
        var cur = f
        while let pid = cur.parentId, let parent = store.folder(pid) { parts.insert(parent.name, at: 0); cur = parent }
        return parts.joined(separator: " / ")
    }

    private func moveSelected(_ folder: Int?) {
        guard !selected.isEmpty else { return }
        store.move(Array(selected), toFolder: folder)
        selected = []
    }

    @ViewBuilder
    private var paperList: some View {
        if store.papers.isEmpty {
            EmptyState(icon: "books.vertical", title: "Your library is empty",
                       message: "Search the databases, drop PDFs into this window, or import a .bib / .ris file from Zotero or Google Scholar.",
                       action: ("Find papers", { nav.section = .search }))
        } else if rows.isEmpty {
            EmptyState(icon: "line.3.horizontal.decrease.circle", title: "Nothing matches",
                       message: "\(store.papers.count) papers are in this review. Try clearing the filters or picking a different folder.")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("\(rows.count) paper\(rows.count == 1 ? "" : "s")")
                        .font(D.small).foregroundStyle(.secondary)
                    Spacer()
                    Button(selected.count == rows.count ? "Deselect all" : "Select all") {
                        selected = selected.count == rows.count ? [] : Set(rows.map(\.id))
                    }
                    .font(D.small)
                }
                .padding(.horizontal, D.s4).padding(.vertical, 6)
                .background(D.surface)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { p in
                            PaperRow(paper: p, selected: selected.contains(p.id)) {
                                if selected.contains(p.id) { selected.remove(p.id) } else { selected.insert(p.id) }
                            }
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Folder tree

enum LibrarySelection: Hashable {
    case all, unfiled, folder(Int)
}

struct FolderTree: View {
    @Binding var selected: LibrarySelection
    var moveTarget: (Int?) -> Void
    @EnvironmentObject var store: Store
    @State private var expanded: Set<Int> = []
    @State private var renaming: Folder? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "Folders")
                Spacer()
                Button { create(parent: nil) } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("New folder in this review")
            }
            .padding(.horizontal, D.s3).padding(.vertical, D.s2)

            List {
                row(.all, "All papers", "tray.full", store.papers.count, depth: 0, folder: nil)
                row(.unfiled, "Unfiled", "tray", store.papers.filter { $0.folderId == nil }.count,
                    depth: 0, folder: nil)
                if !store.folders.isEmpty {
                    SwiftUI.Section {
                        ForEach(visibleFolders, id: \.folder.id) { item in
                            row(.folder(item.folder.id), item.folder.name,
                                store.children(of: item.folder.id).isEmpty ? "folder" : "folder.fill",
                                store.papers(inFolder: item.folder.id).count,
                                depth: item.depth, folder: item.folder)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Text("Right-click a folder to rename it, add a sub-folder, or move the selected papers into it.")
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                .padding(D.s3)
        }
        .sheet(item: $renaming) { f in RenameFolderSheet(folder: f) { renaming = nil } }
    }

    /// Depth-first walk of the folder tree, skipping the children of collapsed folders.
    private var visibleFolders: [(folder: Folder, depth: Int)] {
        var out: [(Folder, Int)] = []
        func walk(_ parent: Int?, _ depth: Int) {
            for f in store.children(of: parent) {
                out.append((f, depth))
                if expanded.contains(f.id) { walk(f.id, depth + 1) }
            }
        }
        walk(nil, 0)
        return out
    }

    private func row(_ sel: LibrarySelection, _ name: String, _ icon: String, _ count: Int,
                     depth: Int, folder: Folder?) -> some View {
        HStack(spacing: 5) {
            if let f = folder, !store.children(of: f.id).isEmpty {
                Button {
                    if expanded.contains(f.id) { expanded.remove(f.id) } else { expanded.insert(f.id) }
                } label: {
                    Image(systemName: expanded.contains(f.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            } else if depth > 0 || folder != nil {
                Spacer().frame(width: 10)
            }
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(folder.map { $0.color } ?? Color.secondary)
            Text(name).font(D.small).lineLimit(1)
            Spacer()
            Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(selected == sel ? Palette.accent.opacity(0.14) : Color.clear)
        .onTapGesture { selected = sel }
        .contextMenu {
            if let f = folder {
                Button("New sub-folder…") { create(parent: f.id) }
                Button("Rename / recolour…") { renaming = f }
                Button("Move selected papers here") { moveTarget(f.id) }
                Divider()
                Button("Delete folder", role: .destructive) {
                    store.deleteFolder(f.id)
                    if selected == .folder(f.id) { selected = .all }
                }
            } else {
                Button("New folder…") { create(parent: nil) }
                if case .unfiled = sel { Button("Move selected papers here") { moveTarget(nil) } }
            }
        }
    }

    private func create(parent: Int?) {
        let alert = NSAlert()
        alert.messageText = parent == nil ? "New folder" : "New sub-folder"
        alert.informativeText = "Folders group the papers inside this review. Nothing is moved on disk."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "e.g. Chapter 2 — tactile perception"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let id = store.addFolder(name: name, parent: parent)
            if let parent { expanded.insert(parent) }
            selected = .folder(id)
        }
    }
}

struct RenameFolderSheet: View {
    let folder: Folder
    var done: () -> Void
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var color = "#8A93A3"
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: D.s4) {
            Text("Folder").font(D.title)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            SectionLabel(text: "Colour")
            HStack(spacing: 6) {
                ForEach(["#8A93A3"] + Palette.highlightHexes, id: \.self) { hex in
                    Button { color = hex } label: {
                        RoundedRectangle(cornerRadius: 5).fill(Color(hex: hex))
                            .frame(width: 26, height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(.primary, lineWidth: color == hex ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save") {
                    var f = folder; f.name = name; f.colorHex = color
                    store.updateFolder(f); done()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(D.s5).frame(width: 420)
        .onAppear { if !loaded { name = folder.name; color = folder.colorHex; loaded = true } }
    }
}

// MARK: - One paper

struct PaperRow: View {
    let paper: Paper
    let selected: Bool
    let toggle: () -> Void

    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var downloader: Downloader
    @EnvironmentObject var engine: SearchEngine
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: D.s3) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .labelsHidden().toggleStyle(.checkbox)

            Button { store.toggleStar(paper.id) } label: {
                Image(systemName: paper.starred ? "star.fill" : "star")
                    .foregroundStyle(paper.starred ? Palette.amber : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(paper.title).font(D.body.weight(.medium)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(paper.authorLine)
                    if let y = paper.year { Text("· \(String(y))") }
                    if !paper.venue.isEmpty { Text("· \(paper.venue)").lineLimit(1) }
                }
                .font(D.small).foregroundStyle(.secondary)

                HStack(spacing: 5) {
                    StageBadge(stage: paper.stage)
                    if let f = store.folder(paper.folderId) {
                        Chip(text: f.name, color: f.color, icon: "folder")
                    }
                    if !paper.sourceDB.isEmpty { Chip(text: paper.sourceDB, color: Palette.slate) }
                    if paper.hasPDF { Chip(text: "PDF", color: Palette.emerald, icon: "doc.fill") }
                    let n = store.evidence(forPaper: paper.id).count
                    if n > 0 { Chip(text: "\(n) highlights", color: Palette.amber, icon: "highlighter") }
                    ForEach(paper.sdgs.prefix(2), id: \.self) { Chip(text: $0, color: Palette.violet, icon: "globe") }
                    if !paper.excludeReason.isEmpty {
                        Text(paper.excludeReason).font(D.small).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            // Actions are full-size labelled buttons — the download in particular was the
            // one thing being hunted for, so it is now the widest control in the row.
            VStack(alignment: .trailing, spacing: 5) {
                if downloader.active[paper.id] != nil {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text(downloader.active[paper.id] ?? "").font(D.small).foregroundStyle(.secondary)
                    }
                    .frame(width: 150, alignment: .trailing)
                } else if !paper.hasPDF {
                    Button {
                        Task { await downloader.fetch(paper: paper, store: store, email: engine.contactEmail) }
                    } label: {
                        Label("Get free PDF", systemImage: "arrow.down.circle.fill")
                            .frame(width: 118)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help("Search Unpaywall and OpenAlex for a legal free copy")
                } else {
                    Button { nav.read(paper.id) } label: {
                        Label("Read", systemImage: "book.fill").frame(width: 118)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                HStack(spacing: 6) {
                    if !paper.url.isEmpty || !paper.doi.isEmpty {
                        Button {
                            if let u = SafeLink.forPaper(url: paper.url, doi: paper.doi) {
                                SafeLink.open(u)
                            } else {
                                store.flash("That record has no usable web link")
                            }
                        } label: { Image(systemName: "arrow.up.forward.square") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Open the source page")
                    }
                    Menu {
                        Button("Open in reader") { nav.read(paper.id) }
                        Button("Copy reference") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(paper.reference, forType: .string)
                            store.flash("Reference copied")
                        }
                        Menu("Move to folder") {
                            Button("Review root") { store.move([paper.id], toFolder: nil) }
                            ForEach(store.folders) { f in
                                Button(f.name) { store.move([paper.id], toFolder: f.id) }
                            }
                        }
                        Menu("Move to stage") {
                            ForEach(Stage.allCases) { s in
                                Button(s.label) { store.setStage(paper.id, s) }
                            }
                        }
                        Divider()
                        Button("Remove from review", role: .destructive) { store.deletePaper(paper.id) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 24)
                }
                .opacity(hovering ? 1 : 0.6)
            }
        }
        .padding(.horizontal, D.s4).padding(.vertical, D.s3)
        .background(selected ? Palette.accent.opacity(0.06) : (hovering ? Color.secondary.opacity(0.04) : .clear))
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { nav.read(paper.id) }
    }
}
