import SwiftUI
import AppKit

/// Where a review stands right now, and the one thing to do next.
struct DashboardView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var assistant: Assistant

    private var p: Store.Prisma { store.prisma }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: D.s5) {
                header
                methodStrip
                stats
                HStack(alignment: .top, spacing: D.s4) {
                    VStack(alignment: .leading, spacing: D.s5) {
                        gapsPanel
                        nextStep
                    }
                    .frame(maxWidth: .infinity)
                    coverage.frame(width: 320)
                }
                if !store.evidence.isEmpty { recentEvidence }
            }
            .padding(D.s5)
        }
        .background(D.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            Text(store.project?.name ?? "No review").font(.system(size: 28, weight: .semibold))
            if let q = store.project?.question, !q.isEmpty {
                Text(q).font(.system(size: 15, design: .serif)).foregroundStyle(.secondary)
            } else {
                Button("Add your review question →") { nav.section = .settings }
                    .buttonStyle(.plain).font(D.body).foregroundStyle(Palette.accent)
            }
        }
    }

    @ViewBuilder
    private var methodStrip: some View {
        if let m = store.activeMethod, !m.blocks.isEmpty {
            Button { nav.section = .method } label: {
                Card(padding: D.s3) {
                    HStack(spacing: D.s3) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(D.small.weight(.semibold))
                            Text("Step \(min(m.currentStep + 1, m.blocks.count)) of \(m.blocks.count)")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        FlowRow(spacing: 3) {
                            ForEach(Array(m.blocks.enumerated()), id: \.offset) { i, b in
                                Chip(text: b.label,
                                     color: i < m.currentStep ? Palette.emerald
                                          : (i == m.currentStep ? Palette.accent : Palette.slate),
                                     filled: i == m.currentStep)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var stats: some View {
        HStack(spacing: D.s3) {
            statCard(p.identified, "Records identified", Palette.slate, .library)
            statCard(p.screened - p.excludedScreening - store.pendingScreening.count, "Passed screening", Palette.amber, .screening)
            statCard(store.papers.filter(\.hasPDF).count, "PDFs in hand", Palette.accent, .reader)
            statCard(store.evidence.count, "Highlights captured", Palette.violet, .evidence)
            statCard(p.included, "Included", Palette.emerald, .prisma)
        }
    }

    private func statCard(_ n: Int, _ label: String, _ tint: Color, _ go: Section) -> some View {
        Button { nav.section = go } label: {
            Card(padding: D.s3) { Stat(value: n, label: label, tint: tint) }
        }
        .buttonStyle(.plain)
    }

    /// What's structurally weak about the review right now. Not advice — each line is a
    /// count of real records, and clicking it goes to them.
    @ViewBuilder
    private var gapsPanel: some View {
        let gaps = store.gaps
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: D.s3) {
                HStack {
                    SectionLabel(text: "What am I missing")
                    Spacer()
                    Text("\(gaps.count) thing\(gaps.count == 1 ? "" : "s") to look at")
                        .font(D.small).foregroundStyle(.tertiary)
                }
                VStack(spacing: D.s2) {
                    ForEach(gaps) { gap in
                        Button {
                            if let s = Section(rawValue: gap.section) { nav.section = s }
                        } label: {
                            Card(padding: D.s3) {
                                HStack(alignment: .top, spacing: D.s3) {
                                    Image(systemName: icon(gap.severity))
                                        .font(.system(size: 14))
                                        .foregroundStyle(tint(gap.severity))
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(gap.title).font(D.body.weight(.medium))
                                        Text(gap.detail).font(D.small).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Text("\(gap.count)")
                                        .font(.system(size: 17, weight: .medium, design: .rounded))
                                        .foregroundStyle(tint(gap.severity))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                            }
                            .background(tint(gap.severity).opacity(gap.severity == .serious ? 0.06 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func icon(_ s: Store.Gap.Severity) -> String {
        switch s {
        case .serious: return "exclamationmark.triangle.fill"
        case .warn: return "exclamationmark.circle"
        case .info: return "info.circle"
        }
    }

    private func tint(_ s: Store.Gap.Severity) -> Color {
        switch s {
        case .serious: return Palette.rose
        case .warn: return Palette.amber
        case .info: return Palette.accent
        }
    }

    private var nextStep: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            SectionLabel(text: "What to do next")
            ForEach(steps, id: \.title) { s in
                Button { nav.section = s.section } label: {
                    Card(padding: D.s3) {
                        HStack(spacing: D.s3) {
                            Image(systemName: s.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(s.done ? Palette.emerald : Palette.accent)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(D.body.weight(.medium))
                                Text(s.detail).font(D.small).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if s.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.emerald) }
                            else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct Step { let title: String; let detail: String; let icon: String; let section: Section; let done: Bool }

    private var steps: [Step] {
        let hasCriteria = !(store.project?.inclusionCriteria.isEmpty ?? true)
        return [
            Step(title: "Write your inclusion and exclusion criteria",
                 detail: hasCriteria ? "Set — screening checks every record against them"
                                     : "Screening can't be systematic without them",
                 icon: "list.bullet.clipboard", section: .settings, done: hasCriteria),
            Step(title: "Search the databases",
                 detail: p.identified == 0 ? "One query, six databases, merged into one list"
                                           : "\(p.identified) records identified so far",
                 icon: "magnifyingglass", section: .search, done: p.identified > 0),
            Step(title: "Remove duplicates",
                 detail: p.duplicates > 0 ? "\(p.duplicates) duplicate records marked"
                                          : "Run duplicate detection in the Library",
                 icon: "doc.on.doc", section: .library, done: p.duplicates > 0 || p.identified == 0),
            Step(title: "Screen titles and abstracts",
                 detail: store.pendingScreening.isEmpty && p.identified > 0
                    ? "Queue is clear" : "\(store.pendingScreening.count) records waiting",
                 icon: "checklist", section: .screening, done: store.pendingScreening.isEmpty && p.identified > 0),
            Step(title: "Read and highlight the full texts",
                 detail: store.evidence.isEmpty ? "Colour-code passages as you read"
                                                : "\(store.evidence.count) highlights across \(Set(store.evidence.map(\.paperId)).count) papers",
                 icon: "highlighter", section: .reader, done: !store.evidence.isEmpty),
            Step(title: "Fill the review matrix",
                 detail: filledCells == 0 ? "Turn highlights into a comparable table"
                                          : "\(filledCells) of \(max(store.included.count * store.columns.count, 1)) cells filled",
                 icon: "tablecells", section: .matrix, done: filledCells > 0),
        ]
    }

    private var filledCells: Int {
        store.cells.values.filter { !$0.value.isEmpty }.count
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            SectionLabel(text: "Evidence by category")
            Card(padding: D.s3) {
                if store.evidence.isEmpty {
                    Text("Nothing highlighted yet. Categories fill in as you read.")
                        .font(D.small).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        let maxN = store.tags.map { store.evidenceCount(forTag: $0.id) }.max() ?? 1
                        ForEach(store.tags) { t in
                            let n = store.evidenceCount(forTag: t.id)
                            if n > 0 {
                                HStack(spacing: 6) {
                                    Text(t.name).font(D.small).frame(width: 96, alignment: .leading).lineLimit(1)
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 2).fill(t.color.opacity(0.75))
                                            .frame(width: max(3, geo.size.width * CGFloat(n) / CGFloat(max(maxN, 1))),
                                                   height: 9)
                                            .frame(maxHeight: .infinity, alignment: .center)
                                    }
                                    .frame(height: 12)
                                    Text("\(n)").font(D.small.monospacedDigit())
                                        .frame(width: 26, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }

            SectionLabel(text: "Papers with no highlights")
            Card(padding: D.s3) {
                let gaps = store.included.filter { store.evidence(forPaper: $0.id).isEmpty }
                if gaps.isEmpty {
                    Text(store.included.isEmpty ? "No papers included yet."
                                                : "Every included paper has been read and coded.")
                        .font(D.small).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(gaps.prefix(6)) { p in
                            Button { nav.read(p.id) } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "circle").font(.system(size: 7)).foregroundStyle(.tertiary)
                                    Text(p.title).font(D.small).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if gaps.count > 6 {
                            Text("+ \(gaps.count - 6) more").font(D.small).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var recentEvidence: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            HStack {
                SectionLabel(text: "Latest highlights")
                Spacer()
                Button("See all →") { nav.section = .evidence }.buttonStyle(.plain).font(D.small)
                    .foregroundStyle(Palette.accent)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 440), spacing: D.s3)],
                      alignment: .leading, spacing: D.s3) {
                ForEach(store.evidence.sorted { $0.createdAt > $1.createdAt }.prefix(6)) { e in
                    EvidenceCard(evidence: e, paper: store.paper(e.paperId), compact: false) {
                        nav.read(e.paperId)
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var engine: SearchEngine
    @State private var draft: Project? = nil
    @AppStorage("sieve.contactEmail") private var contactEmail = ""
    @AppStorage("sieve.ai") private var aiEnabled = true


    /// CORE takes an optional key that only raises its rate limit, so it isn't declared
    /// as a gating `keyDefault` — but the field still belongs in Settings.
    private func optionalKeyName(_ p: any SearchProvider) -> String? {
        p.name == "CORE" ? "sieve.corekey" : nil
    }

    private func keyBinding(_ name: String) -> Binding<String> {
        Binding(get: { KeyStore.get(name) },
                set: { KeyStore.set($0, for: name); engineRefresh += 1 })
    }

    @State private var engineRefresh = 0
    @State private var appearanceTick = 0
    @State private var libraryTick = 0
    @State private var mirrorTick = 0

    /// Moves the whole library. Paths are relative to the root, so nothing inside changes.
    private func relocate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move library here"
        panel.message = "Choose a folder to hold the Sieve library"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let dest = dir.appendingPathComponent("Sieve", isDirectory: true)
        do {
            try LibraryMigration.relocate(to: dest, store: store)
            libraryTick += 1
            let alert = NSAlert()
            alert.messageText = "Library moved"
            alert.informativeText = "It now lives at \(dest.path). Quit and reopen Sieve to load it from there."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            store.flash("Could not move the library: \(error.localizedDescription)")
        }
    }

    /// Sorts shared PDFs into per-review folders and reports whatever is left over.
    private func tidy() {
        let report = LibraryMigration.run(store)
        libraryTick += 1
        let alert = NSAlert()
        alert.messageText = "Library sorted"
        var lines: [String] = []
        if report.moved > 0 { lines.append("Moved \(report.moved) PDFs into their own review's folder.") }
        if report.alreadyPlaced > 0 { lines.append("\(report.alreadyPlaced) were already in the right place.") }
        if report.missing > 0 { lines.append("\(report.missing) records pointed at files that are gone; those links were cleared.") }
        if !report.orphans.isEmpty {
            let mb = Double(report.orphanBytes) / 1024 / 1024
            lines.append("")
            lines.append(String(format: "%d files are left that no record points at (%.0f MB). These are the duplicates an older build made when the same PDF was dropped more than once.", report.orphans.count, mb))
        }
        alert.informativeText = lines.joined(separator: "\n")
        if report.orphans.isEmpty {
            alert.addButton(withTitle: "Done")
            alert.runModal()
        } else {
            alert.addButton(withTitle: "Move them to the Trash")
            alert.addButton(withTitle: "Leave them")
            if alert.runModal() == .alertFirstButtonReturn {
                for file in report.orphans { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
                store.flash("Moved \(report.orphans.count) unreferenced files to the Trash")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: D.s5) {
                Text("Settings").font(.system(size: 26, weight: .semibold))

                if let p = store.project {
                    group("This review") {
                        labelled("Name") {
                            TextField("", text: binding(\.name, p)).textFieldStyle(.roundedBorder)
                        }
                        labelled("Review question") {
                            TextField("The one question this review answers",
                                      text: binding(\.question, p), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(2, reservesSpace: true)
                        }
                        labelled("Include a paper if…") {
                            TextField("peer-reviewed · 2015 or later · reports an empirical study",
                                      text: binding(\.inclusionCriteria, p), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(4, reservesSpace: true)
                        }
                        labelled("Exclude a paper if…") {
                            TextField("not in English · no user study · editorial or opinion",
                                      text: binding(\.exclusionCriteria, p), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(4, reservesSpace: true)
                        }
                        Text("Screening checks each record against these, and Claude uses them verbatim when you ask for a recommendation.")
                            .font(D.small).foregroundStyle(.tertiary)
                    }
                }

                group("Appearance") {
                    Picker("", selection: Binding(
                        get: { Appearance.current },
                        set: { Appearance.current = $0; appearanceTick += 1 })) {
                        ForEach(Appearance.allCases) { a in
                            Label(a.label, systemImage: a.icon).tag(a)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 340)
                    Text("Tag colours darken automatically in light mode so they still carry text.")
                        .font(D.small).foregroundStyle(.secondary)
                }

                group("Evidence for retrieval") {
                    Toggle(isOn: Binding(
                        get: { store.strictRetrieval },
                        set: { store.strictRetrieval = $0 })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("A report counts as retrieved only if its PDF is on disk").font(D.body)
                            Text("PRISMA separates reports sought from reports retrieved. With this on, a record with no readable full text is counted as “not retrieved”, however you screened it — the file is the proof.")
                                .font(D.small).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    let missing = store.missingFullTexts.count
                    let broken = store.brokenPDFs.count
                    if missing > 0 || broken > 0 {
                        HStack(spacing: D.s2) {
                            if missing > 0 {
                                Chip(text: "\(missing) past screening with no PDF",
                                     color: Palette.amber, icon: "exclamationmark.triangle.fill")
                            }
                            if broken > 0 {
                                Chip(text: "\(broken) unreadable file\(broken == 1 ? "" : "s")",
                                     color: Palette.rose, icon: "xmark.octagon.fill")
                            }
                            Spacer()
                            Button("Mark the missing ones as not retrieved") {
                                let n = store.markMissingAsNotRetrieved()
                                store.flash(n == 0 ? "Nothing to change"
                                                   : "Moved \(n) records to “not retrieved”")
                            }
                            .font(D.small)
                        }
                    } else {
                        Text("Every record past screening has a verified full text.")
                            .font(D.small).foregroundStyle(Palette.emerald)
                    }
                }

                group("Folders you can browse in Finder") {
                    Text("Sieve can mirror the review into real folders — by decision, by collection, by year — using symbolic links. The same paper appears everywhere it belongs and still takes up space once. Delete the folder any time; nothing is lost.")
                        .font(D.small).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(FinderMirror.Grouping.allCases) { g in
                        Toggle(isOn: Binding(
                            get: { FinderMirror.enabledGroupings.contains(g) },
                            set: { on in
                                var set = FinderMirror.enabledGroupings
                                if on { set.insert(g) } else { set.remove(g) }
                                FinderMirror.enabledGroupings = set
                                mirrorTick += 1
                            })) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(g.label).font(D.body)
                                Text(g.blurb).font(D.small).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { FinderMirror.autoRefresh },
                        set: { FinderMirror.autoRefresh = $0; mirrorTick += 1 })) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Keep it up to date").font(D.body)
                            Text("Rebuild whenever you open the Library, so the folders follow your decisions.")
                                .font(D.small).foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Build the folders now") {
                            let r = FinderMirror.rebuild(store)
                            mirrorTick += 1
                            store.flash(r.links == 0
                                ? "Nothing to mirror yet — no PDFs in this review"
                                : "\(r.links) links across \(r.folders) folders, 0 bytes used")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(FinderMirror.enabledGroupings.isEmpty)

                        Button("Open in Finder") {
                            guard let p = store.project else { return }
                            NSWorkspace.shared.open(Library.reviewDir(id: p.id, name: p.name))
                        }
                        Spacer()
                    }
                    .id(mirrorTick)
                }

                group("File names") {
                    Text("Files are named year-author-title. An earlier build stripped titles to plain letters, which turned a Cyrillic or Greek title into a row of underscores; those are transliterated now.")
                        .font(D.small).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Rename this review's files to match") {
                            let n = FinderMirror.renameFiles(store)
                            store.flash(n == 0 ? "Every file is already named that way"
                                               : "Renamed \(n) files")
                        }
                        Spacer()
                    }
                }

                group("Databases") {
                    Text("Sieve queries these in parallel. The first nine are free and need no account; the rest issue a free key that unlocks them.")
                        .font(D.small).foregroundStyle(.secondary)
                    ForEach(SearchEngine.allProviders, id: \.name) { p in
                        HStack(alignment: .top, spacing: D.s3) {
                            Toggle(isOn: Binding(
                                get: { engine.enabled.contains(p.name) },
                                set: { on in
                                    if on { engine.enabled.insert(p.name) } else { engine.enabled.remove(p.name) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 5) {
                                        Text(p.name).font(D.body)
                                        if p.needsKey && !p.isReady {
                                            Chip(text: "key needed", color: Palette.amber, icon: "key.fill")
                                        } else if p.needsKey {
                                            Chip(text: "key set", color: Palette.emerald, icon: "checkmark")
                                        }
                                    }
                                    Text(p.blurb).font(D.small).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(p.needsKey && !p.isReady)
                            Spacer()
                            if let keyName = p.keyDefault ?? (p.signupURL != nil ? optionalKeyName(p) : nil) {
                                HStack(spacing: 4) {
                                    SecureField("paste key", text: keyBinding(keyName))
                                        .textFieldStyle(.roundedBorder).frame(width: 170).font(D.small)
                                    if let signup = p.signupURL, let u = URL(string: signup) {
                                        Link(destination: u) { Image(systemName: "arrow.up.forward.square") }
                                            .help("Get a free key")
                                    }
                                }
                            }
                        }
                        Divider()
                    }

                    labelled("Results per database") {
                        Stepper("\(engine.perProviderLimit)", value: $engine.perProviderLimit, in: 10...100, step: 5)
                            .frame(width: 140)
                    }
                    labelled("Contact email (optional)") {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("you@university.edu", text: $contactEmail)
                                .textFieldStyle(.roundedBorder).frame(width: 280)
                            Text("OpenAlex, Crossref, PubMed and Unpaywall give faster, more complete results to requests that identify a contact. It is sent only to those services, and only if you fill it in.")
                                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                group("Sites with no API") {
                    Text("These can't be queried programmatically — Google Scholar and BASE block it, and the publishers gate search behind institutional agreements. Sieve opens your search in the browser instead; export citations there as .bib or .ris and drop the file into this window.")
                        .font(D.small).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowRow(spacing: 5) {
                        ForEach(ExternalSite.all) { site in
                            Chip(text: site.name, color: Palette.slate, icon: "arrow.up.forward")
                        }
                    }
                }

                group("Claude assistant") {
                    if Assistant.isAvailable {
                        Toggle("Enable the assistant", isOn: $aiEnabled)
                        Text("Found at \(Assistant.binaryPath ?? "")").font(D.mono).foregroundStyle(.tertiary)
                    } else {
                        Label("The `claude` command-line tool wasn't found on this Mac.", systemImage: "exclamationmark.triangle")
                            .font(D.body).foregroundStyle(Palette.amber)
                        Text("Everything else works without it. Install Claude Code to enable tag suggestions, abstract screening and matrix drafting.")
                            .font(D.small).foregroundStyle(.secondary)
                    }
                    Text("The assistant never records a decision for you. It suggests; you decide. Anything it writes carries an AI badge.")
                        .font(D.small).foregroundStyle(.secondary)
                }

                group("Library") {
                    labelled("Location") {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(Library.root.path).font(D.mono).textSelection(.enabled).lineLimit(1)
                                Button("Reveal") { NSWorkspace.shared.open(Library.root) }
                                Button("Move…") { relocate() }
                                if Library.isCustomLocation {
                                    Button("Reset") {
                                        Library.resetRoot(); libraryTick += 1
                                        store.flash("Back to ~/Documents/Sieve — restart Sieve to load it")
                                    }
                                }
                            }
                            Text("Put the library on an external drive or in a synced folder. Paths are stored relative to this folder, so moving it doesn't break any record.")
                                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    labelled("How it is arranged") {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reviews/<review>/PDFs/ — one file per paper, one folder per review")
                                .font(D.mono)
                            Text("Collections are labels, not locations, so the papers themselves stay flat — a paper in three collections is still one file.")
                                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if LibraryMigration.needsMigration(store) {
                        HStack(alignment: .top, spacing: D.s2) {
                            Image(systemName: "shippingbox").foregroundStyle(Palette.amber)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("PDFs from every review are still in one shared folder")
                                    .font(D.body.weight(.medium))
                                Text("Sorting them into per-review folders also finds files that no record points at — early builds copied a new one every time the same PDF was dropped.")
                                    .font(D.small).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Sort them out…") { tidy() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    HStack {
                        Button("Export everything into one folder…") { Exporters.exportEverything(store) }
                            .buttonStyle(.borderedProminent)
                        Button("Full report as PDF") { Exporters.exportReportPDF(store) }
                        Button("Matrix as Excel") { Exporters.exportMatrixXLSX(store, rows: store.included) }
                    }
                    Text("The folder export writes the report PDF, the matrix as .xlsx/.pdf/.csv, the PRISMA flow, every highlight, a BibTeX file, the full library and your search history — with a README explaining each file.")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.projects.count > 1, let p = store.project {
                    group("Danger zone") {
                        Button("Delete “\(p.name)” and everything in it", role: .destructive) {
                            let alert = NSAlert()
                            alert.messageText = "Delete this review?"
                            alert.informativeText = "\(store.papers.count) records, \(store.evidence.count) highlights and the matrix will be removed. PDFs stay in the library folder."
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn { store.deleteProject(p.id) }
                        }
                    }
                }
            }
            .padding(D.s5).frame(maxWidth: 760, alignment: .leading)
        }
        .background(D.canvas)
    }

    private func binding(_ key: WritableKeyPath<Project, String>, _ p: Project) -> Binding<String> {
        Binding(get: { store.project?[keyPath: key] ?? "" },
                set: { var q = p; q[keyPath: key] = $0; store.updateProject(q) })
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: D.s3) {
            SectionLabel(text: title)
            Card { VStack(alignment: .leading, spacing: D.s3) { content() } }
        }
    }

    private func labelled<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(D.small).foregroundStyle(.secondary)
            content()
        }
    }
}
