import SwiftUI
import AppKit

/// One query, six databases, one merged list. The provenance of every hit stays
/// visible — you can always see which database it came from and what you searched.
struct SearchView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: SearchEngine
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var nav: Navigator
    @State private var selection = Set<String>()
    @State private var expanded: String? = nil
    @State private var suggestions: [String] = []
    @State private var showSuggestions = false
    @State private var showExternal = false
    @State private var showDates = false
    @State private var targetFolder: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            queryBar
            providerBar
            Divider()
            if engine.results.isEmpty && !engine.running {
                EmptyState(icon: "magnifyingglass",
                           title: "Search every database at once",
                           message: "One query goes to OpenAlex, Crossref, Semantic Scholar, Europe PMC, arXiv and DOAJ simultaneously. Records that describe the same paper are merged into one row, so you screen each paper once — not six times.")
            } else {
                resultList
            }
        }
        .background(D.canvas)
        .sheet(isPresented: $showExternal) { ExternalSitesSheet(query: engine.query) { showExternal = false } }
    }

    // MARK: Query bar

    private var queryBar: some View {
        VStack(spacing: D.s3) {
            HStack(spacing: D.s2) {
                SearchField(placeholder: "Search terms — e.g. haptic feedback low vision navigation",
                            text: $engine.query) { Task { await engine.run() } }
                    .frame(maxWidth: .infinity)

                if Assistant.isAvailable && assistant.enabled {
                    Button {
                        Task {
                            guard let out = await assistant.buildQueries(
                                question: store.project?.question.isEmpty == false
                                    ? store.project!.question : engine.query) else { return }
                            suggestions = out.components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-• \t")) }
                                .filter { $0.count > 3 }
                            showSuggestions = !suggestions.isEmpty
                        }
                    } label: {
                        Label("Suggest queries", systemImage: "sparkle")
                    }
                    .disabled(assistant.busy || (store.project?.question.isEmpty ?? true) && engine.query.isEmpty)
                    .help("Ask Claude for alternative search strings based on your review question")
                }

                Button {
                    Task { await engine.run() }
                } label: {
                    if engine.running { ProgressView().controlSize(.small).frame(width: 40) }
                    else { Text("Search").frame(width: 40) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(engine.query.trimmingCharacters(in: .whitespaces).isEmpty || engine.running)
                .keyboardShortcut(.return, modifiers: .command)
            }

            if showSuggestions {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Claude's suggested search strings", systemImage: "sparkle")
                            .font(D.small).foregroundStyle(Palette.violet)
                        Spacer()
                        Button("Hide") { showSuggestions = false }.buttonStyle(.plain).font(D.small)
                    }
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            engine.query = s
                            showSuggestions = false
                            Task { await engine.run() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                                Text(s).font(D.small)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
                .padding(D.s3)
                .background(Palette.violet.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: D.radius))
            }
        }
        .padding(D.s4)
    }

    // MARK: Provider status + filters

    private var providerBar: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            HStack(alignment: .top, spacing: D.s3) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        SectionLabel(text: "Databases searched at once")
                        Button(allOn ? "None" : "All") {
                            engine.enabled = allOn ? [] : Set(SearchEngine.allProviders.filter(\.isReady).map(\.name))
                        }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.accent)
                    }
                    FlowRow(spacing: 5) {
                        ForEach(SearchEngine.allProviders, id: \.name) { p in
                            providerToggle(p)
                        }
                    }
                }
                Spacer(minLength: D.s4)
                filters
            }
            HStack(spacing: 5) {
                Text("No API:").font(.system(size: 10)).foregroundStyle(.tertiary)
                ForEach(ExternalSite.all.prefix(6)) { site in
                    Button { openExternal(site) } label: {
                        Chip(text: site.name, color: Palette.slate, icon: "arrow.up.forward")
                    }
                    .buttonStyle(.plain)
                    .help("\(site.blurb)\n\nOpens in your browser. \(site.howTo)")
                }
                Button("more…") { showExternal = true }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, D.s4)
        .padding(.bottom, D.s3)
    }

    private var allOn: Bool {
        !engine.enabled.isEmpty
    }

    private func openExternal(_ site: ExternalSite) {
        let q = engine.query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { store.flash("Type a search first"); return }
        guard let url = site.url(for: q) else { return }
        NSWorkspace.shared.open(url)
        store.flash("Opened \(site.name). \(site.howTo)")
    }

    private func providerToggle(_ p: any SearchProvider) -> some View {
        let on = engine.enabled.contains(p.name)
        let state = engine.progress[p.name]
        let locked = p.needsKey && !p.isReady
        return Button {
            if locked { nav.section = .settings; return }
            if on { engine.enabled.remove(p.name) } else { engine.enabled.insert(p.name) }
        } label: {
            HStack(spacing: 5) {
                if locked {
                    Image(systemName: "key.fill").font(.system(size: 8))
                } else {
                    switch state {
                    case .running: ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 8, height: 8)
                    case .done(let n): Text("\(n)").font(D.small.monospacedDigit().weight(.semibold))
                    case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8))
                    default: Circle().fill(on ? Palette.accent : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                    }
                }
                Text(p.name).font(D.small)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(locked ? Color.secondary.opacity(0.05)
                               : (on ? Palette.accent.opacity(0.12) : Color.secondary.opacity(0.07)))
            .foregroundStyle(locked ? Color.secondary.opacity(0.7) : stateColor(state, on: on))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(locked ? Color.secondary.opacity(0.25) : .clear,
                                      style: StrokeStyle(lineWidth: 0.8, dash: [3, 2])))
        }
        .buttonStyle(.plain)
        .help(locked ? "\(p.name) needs a free API key — click to add one in Settings"
                     : helpText(p, state))
    }

    private func stateColor(_ s: SearchEngine.ProviderState?, on: Bool) -> Color {
        if case .failed = s { return Palette.rose }
        return on ? Palette.accent : .secondary
    }

    private func helpText(_ p: any SearchProvider, _ s: SearchEngine.ProviderState?) -> String {
        if case .failed(let why) = s { return "\(p.name): \(why). Other databases still returned results." }
        return "\(p.name) — \(p.blurb)"
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Narrow the results")
            HStack(spacing: D.s2) {
                Picker("", selection: $engine.sort) {
                    ForEach(SearchEngine.Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 108)
                Toggle("Free PDF only", isOn: $engine.onlyWithPDF)
                    .toggleStyle(.checkbox).font(D.small)
            }
            HStack(spacing: 4) {
                Text("Years").font(D.small).foregroundStyle(.secondary)
                yearBox("from", $engine.yearFrom)
                Text("–").foregroundStyle(.secondary)
                yearBox("to", $engine.yearTo)
                Menu {
                    Button("Last 2 years") { setYears(2) }
                    Button("Last 5 years") { setYears(5) }
                    Button("Last 10 years") { setYears(10) }
                    Button("Any year") { engine.yearFrom = nil; engine.yearTo = nil
                                         engine.dateFrom = nil; engine.dateTo = nil }
                    Divider()
                    Button("Exact dates…") { showDates = true }
                } label: { Image(systemName: "calendar") }
                    .menuStyle(.borderlessButton).frame(width: 26)
                    .popover(isPresented: $showDates) { datePopover }
            }
            HStack(spacing: 4) {
                Text("Author").font(D.small).foregroundStyle(.secondary)
                TextField("surname", text: $engine.authorFilter)
                    .textFieldStyle(.roundedBorder).frame(width: 96).font(D.small)
                if !engine.availableSDGs.isEmpty {
                    Menu {
                        Button("Any goal") { engine.sdgFilter = [] }
                        Divider()
                        ForEach(engine.availableSDGs, id: \.self) { g in
                            Button {
                                if engine.sdgFilter.contains(g) { engine.sdgFilter.remove(g) }
                                else { engine.sdgFilter.insert(g) }
                            } label: {
                                Text(engine.sdgFilter.contains(g) ? "✓ \(g)" : g)
                            }
                        }
                    } label: {
                        Label(engine.sdgFilter.isEmpty ? "SDG" : "SDG (\(engine.sdgFilter.count))",
                              systemImage: "globe")
                    }
                    .frame(width: 96)
                }
            }
        }
    }

    private func setYears(_ back: Int) {
        let now = Calendar.current.component(.year, from: Date())
        engine.yearFrom = now - back
        engine.yearTo = nil
        engine.dateFrom = nil; engine.dateTo = nil
    }

    private var datePopover: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Text("Publication date").font(D.heading)
            Text("Records without a full date are kept, since most databases only report a year.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary).frame(width: 260)
            DatePicker("From", selection: Binding(
                get: { engine.dateFrom ?? Calendar.current.date(byAdding: .year, value: -5, to: Date())! },
                set: { engine.dateFrom = $0 }), displayedComponents: .date)
            DatePicker("To", selection: Binding(
                get: { engine.dateTo ?? Date() },
                set: { engine.dateTo = $0 }), displayedComponents: .date)
            HStack {
                Button("Clear") { engine.dateFrom = nil; engine.dateTo = nil; showDates = false }
                Spacer()
                Button("Done") { showDates = false }.buttonStyle(.borderedProminent)
            }
        }
        .padding(D.s4).frame(width: 300)
    }

    private func yearBox(_ label: String, _ value: Binding<Int?>) -> some View {
        TextField(label, text: Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0) }))
            .textFieldStyle(.roundedBorder)
            .frame(width: 58)
            .font(D.small)
    }

    // MARK: Results

    private var resultList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(engine.filtered.count) unique papers")
                    .font(D.small).foregroundStyle(.secondary)
                if engine.results.count != engine.filtered.count {
                    Text("· \(engine.results.count - engine.filtered.count) hidden by filters")
                        .font(D.small).foregroundStyle(.tertiary)
                }
                Spacer()
                if !selection.isEmpty {
                    Text("\(selection.count) selected").font(D.small).foregroundStyle(.secondary)
                    Button("Add to review") { addSelected(fetchPDFs: false) }
                    Button("Add + get free PDFs") { addSelected(fetchPDFs: true) }
                        .buttonStyle(.borderedProminent)
                }
                if !store.folders.isEmpty {
                    Menu {
                        Button("Review root") { targetFolder = nil }
                        ForEach(store.folders) { f in Button(f.name) { targetFolder = f.id } }
                    } label: {
                        Label(store.folder(targetFolder)?.name ?? "No folder", systemImage: "folder")
                    }
                    .frame(width: 140)
                    .help("Where added papers go")
                }
                Button(selection.count == engine.filtered.count ? "Deselect all" : "Select all") {
                    if selection.count == engine.filtered.count { selection = [] }
                    else { selection = Set(engine.filtered.map(\.id)) }
                }
                .font(D.small)
            }
            .padding(.horizontal, D.s4).padding(.vertical, D.s2)
            .background(D.surface)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(engine.filtered) { hit in
                        HitRow(hit: hit,
                               selected: selection.contains(hit.id),
                               expanded: expanded == hit.id,
                               alreadyIn: alreadyInReview(hit),
                               toggle: {
                                   if selection.contains(hit.id) { selection.remove(hit.id) }
                                   else { selection.insert(hit.id) }
                               },
                               expand: { expanded = expanded == hit.id ? nil : hit.id })
                        Divider()
                    }
                }
            }
        }
    }

    private func alreadyInReview(_ hit: SearchHit) -> Bool {
        store.papers.contains { $0.dedupeKey == hit.dedupeKey }
    }

    private func addSelected(fetchPDFs: Bool) {
        let chosen = engine.filtered.filter { selection.contains($0.id) }
        var added = 0
        var newIds: [Int] = []
        for hit in chosen {
            if let id = store.addPaper(from: hit, query: engine.query, folder: targetFolder) {
                added += 1; newIds.append(id)
            }
        }
        store.reloadPapers()
        store.logSearchRun(query: engine.query,
                           providers: Array(engine.enabled),
                           results: engine.results.count,
                           imported: added)
        selection = []
        let skipped = chosen.count - added
        store.flash("Added \(added) paper\(added == 1 ? "" : "s")" +
                    (skipped > 0 ? " · \(skipped) already in this review" : ""))

        if fetchPDFs {
            let downloader = Downloader()
            Task { @MainActor in
                for id in newIds {
                    guard let p = store.paper(id) else { continue }
                    await downloader.fetch(paper: p, store: store, email: engine.contactEmail)
                }
                store.flash("Finished fetching open-access PDFs")
            }
        }
    }
}

// MARK: - One search result

struct HitRow: View {
    let hit: SearchHit
    let selected: Bool
    let expanded: Bool
    let alreadyIn: Bool
    let toggle: () -> Void
    let expand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            HStack(alignment: .top, spacing: D.s3) {
                Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                    .labelsHidden().toggleStyle(.checkbox)
                    .disabled(alreadyIn)

                VStack(alignment: .leading, spacing: 4) {
                    Text(hit.title)
                        .font(D.body.weight(.medium))
                        .lineLimit(expanded ? nil : 2)
                        .foregroundStyle(alreadyIn ? .secondary : .primary)

                    HStack(spacing: 6) {
                        Text(hit.authors.isEmpty ? "Unknown author" :
                                (hit.authors.count > 3 ? "\(hit.authors[0]) et al." : hit.authors.joined(separator: ", ")))
                        if let y = hit.year { Text("·"); Text(String(y)) }
                        if !hit.venue.isEmpty { Text("·"); Text(hit.venue).lineLimit(1) }
                    }
                    .font(D.small).foregroundStyle(.secondary)

                    HStack(spacing: 5) {
                        Chip(text: hit.provider, color: Palette.accent)
                        ForEach(hit.mergedFrom, id: \.self) { m in
                            Chip(text: m, color: Palette.slate)
                        }
                        if !hit.pdfURL.isEmpty { Chip(text: "Free PDF", color: Palette.emerald, icon: "arrow.down.circle") }
                        if hit.citedBy > 0 { Chip(text: "\(hit.citedBy) citations", color: Palette.slate) }
                        if alreadyIn { Chip(text: "Already in review", color: Palette.amber, icon: "checkmark") }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    if !hit.abstract.isEmpty {
                        Button(expanded ? "Less" : "Abstract") { expand() }
                            .buttonStyle(.plain).font(D.small).foregroundStyle(Palette.accent)
                    }
                    if !hit.url.isEmpty {
                        Button {
                            if let u = URL(string: hit.url.hasPrefix("http") ? hit.url : "https://doi.org/\(hit.doi)") {
                                NSWorkspace.shared.open(u)
                            }
                        } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(hit.url)
                    }
                }
            }

            if expanded, !hit.abstract.isEmpty {
                Text(hit.abstract)
                    .font(D.serif)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 26)
                    .padding(.trailing, D.s4)
            }
        }
        .padding(.horizontal, D.s4).padding(.vertical, D.s3)
        .background(selected ? Palette.accent.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if !alreadyIn { toggle() } }
    }
}
