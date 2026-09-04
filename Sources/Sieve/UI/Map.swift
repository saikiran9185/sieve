import SwiftUI
import AppKit

/// A map of the corpus. Papers are nodes; an edge means the two papers cite the same work
/// (bibliographic coupling) or one cites the other. Both come from the reference lists
/// OpenAlex ships with every record, so the map is built from real citation data.
///
/// It also finds the works your papers cite most often but that aren't in your library yet —
/// the reading you're missing — and offers to add them.
struct MapView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @StateObject private var graph = GraphModel()

    @State private var selectedId: Int? = nil
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var colorBy: ColorBy = .stage
    @State private var showSuggestions = true
    @AppStorage("sieve.mapPanelWidth") private var panelWidth: Double = 320

    enum ColorBy: String, CaseIterable, Identifiable {
        case stage = "Stage", folder = "Folder", year = "Year"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if graph.nodes.isEmpty {
                EmptyState(icon: "point.3.connected.trianglepath.dotted",
                           title: "Nothing to map yet",
                           message: "Add papers through Find papers, then come back.",
                           action: ("Find papers", { nav.section = .search }))
            } else if graph.edges.isEmpty && !store.papers.contains(where: { !$0.references.isEmpty }) {
                // Papers added before reference lists were collected have nothing to connect.
                EmptyState(icon: "arrow.clockwise.circle",
                           title: "These papers have no citation data yet",
                           message: "The map is drawn from the works each paper cites. Your \(store.papers.count) papers were added without that data — run “Fill in missing details” in the Library and Sieve will fetch the reference lists from OpenAlex, then this map will draw itself.",
                           action: ("Go to the Library", { nav.section = .library }))
            } else {
                HStack(spacing: 0) {
                    canvas.frame(maxWidth: .infinity)
                    if selectedId != nil || (!graph.suggestions.isEmpty && showSuggestions) {
                        PaneDivider(width: $panelWidth, range: 260...520, sizesTrailingPane: true)
                        Group {
                            if let id = selectedId, let p = store.paper(id) {
                                MapDetail(paper: p, graph: graph)
                            } else {
                                SuggestionPanel(graph: graph)
                            }
                        }
                        .frame(width: panelWidth)
                    }
                }
            }
        }
        .background(D.canvas)
        .onAppear { graph.build(from: store) }
        .onChange(of: store.papers.count) { _, _ in graph.build(from: store) }
    }

    private var toolbar: some View {
        Toolbar {
            Text("Map").font(D.body.weight(.medium))
            Text("\(graph.nodes.count) papers · \(graph.edges.count) connections")
                .font(D.small).foregroundStyle(.secondary)
            Picker("", selection: $colorBy) {
                ForEach(ColorBy.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 190)

            Slider(value: $graph.linkThreshold, in: 1...6, step: 1) { Text("Links") }
                .frame(width: 90)
                .onChange(of: graph.linkThreshold) { _, _ in graph.build(from: store) }
            Text("≥\(Int(graph.linkThreshold)) shared refs")
                .font(D.small).foregroundStyle(.secondary)

            Spacer()
            Button {
                Task { await graph.findSuggestions(store: store) }
            } label: {
                if graph.loadingSuggestions { HStack { ProgressView().controlSize(.small); Text("Looking…") } }
                else { Label("Find what I'm missing", systemImage: "sparkle.magnifyingglass") }
            }
            .disabled(graph.loadingSuggestions)
            .help("Works your papers cite repeatedly that aren't in your library yet")

            Button { withAnimation { zoom = 1; pan = .zero; graph.relayout() } } label: {
                Label("Re-layout", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                func place(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: center.x + p.x * zoom, y: center.y + p.y * zoom)
                }

                // Edges first so nodes sit on top of them.
                for e in graph.edges {
                    guard let a = graph.position[e.a], let b = graph.position[e.b] else { continue }
                    var path = Path()
                    path.move(to: place(a)); path.addLine(to: place(b))
                    let strong = e.weight >= 4
                    ctx.stroke(path,
                               with: .color(Color.secondary.opacity(strong ? 0.32 : 0.14)),
                               lineWidth: strong ? 1.4 : 0.7)
                }

                for n in graph.nodes {
                    guard let pos = graph.position[n.id] else { continue }
                    let pt = place(pos)
                    let r = radius(n) * zoom
                    let isSelected = selectedId == n.id
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(tint(n).opacity(0.85)))
                    if isSelected {
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                                   with: .color(.primary), lineWidth: 2)
                    }
                    if zoom > 0.75 || isSelected {
                        let label = Text(n.label)
                            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        ctx.draw(label, at: CGPoint(x: pt.x, y: pt.y + r + 8), anchor: .top)
                    }
                }

                // Suggested reading is drawn as hollow rings — clearly not yours yet.
                if showSuggestions {
                    for s in graph.suggestions {
                        guard let pos = graph.suggestionPosition[s.openAlexId] else { continue }
                        let pt = place(pos)
                        let r = 5 * zoom
                        let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(Palette.violet), lineWidth: 1.4)
                        if zoom > 0.9 {
                            ctx.draw(Text("\(s.citedByMine)×").font(.system(size: 8))
                                        .foregroundStyle(Palette.violet),
                                     at: CGPoint(x: pt.x, y: pt.y + r + 7), anchor: .top)
                        }
                    }
                }
            }
            .background(D.raised)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in pan = CGSize(width: dragStart.width + v.translation.width,
                                                   height: dragStart.height + v.translation.height) }
                    .onEnded { _ in dragStart = pan }
            )
            .onTapGesture { location in
                let center = CGPoint(x: geo.size.width / 2 + pan.width, y: geo.size.height / 2 + pan.height)
                var best: (Int, CGFloat)? = nil
                for n in graph.nodes {
                    guard let p = graph.position[n.id] else { continue }
                    let pt = CGPoint(x: center.x + p.x * zoom, y: center.y + p.y * zoom)
                    let d = hypot(pt.x - location.x, pt.y - location.y)
                    if d < max(radius(n) * zoom + 6, 12), best == nil || d < best!.1 { best = (n.id, d) }
                }
                selectedId = best?.0
            }
            .overlay(alignment: .bottomLeading) { legend.padding(D.s3) }
            .overlay(alignment: .bottomTrailing) { zoomControls.padding(D.s3) }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { withAnimation { zoom = max(0.25, zoom - 0.2) } } label: { Image(systemName: "minus") }
            Button { withAnimation { zoom = min(3, zoom + 0.2) } } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.bordered)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Bigger dot = more highlights · line = shared references")
                .font(.system(size: 9.5)).foregroundStyle(.secondary)
            if !graph.suggestions.isEmpty && showSuggestions {
                HStack(spacing: 4) {
                    Circle().stroke(Palette.violet, lineWidth: 1.4).frame(width: 8, height: 8)
                    Text("\(graph.suggestions.count) works you cite but haven't read")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.violet)
                    Button("hide") { showSuggestions = false }.font(.system(size: 9.5)).buttonStyle(.plain)
                }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func radius(_ n: GraphModel.Node) -> CGFloat {
        let highlights = store.evidence.filter { $0.paperId == n.id }.count
        return 6 + min(CGFloat(highlights) * 0.8, 10)
    }

    private func tint(_ n: GraphModel.Node) -> Color {
        guard let p = store.paper(n.id) else { return Palette.slate }
        switch colorBy {
        case .stage: return p.stage.color
        case .folder: return store.folder(p.folderId)?.color ?? Palette.slate
        case .year:
            guard let y = p.year else { return Palette.slate }
            let years = store.papers.compactMap(\.year)
            guard let lo = years.min(), let hi = years.max(), hi > lo else { return Palette.accent }
            let t = Double(y - lo) / Double(hi - lo)
            return Color(hue: 0.62 - t * 0.45, saturation: 0.6, brightness: 0.8)
        }
    }
}

// MARK: - Graph model

@MainActor
final class GraphModel: ObservableObject {
    struct Node: Identifiable { let id: Int; let label: String; let refs: Set<String>; let oaId: String }
    struct Edge { let a: Int; let b: Int; let weight: Int }
    struct Suggestion: Identifiable {
        var id: String { openAlexId }
        let openAlexId: String
        var title: String = ""
        var authors: [String] = []
        var year: Int?
        var doi: String = ""
        var citedByMine: Int
    }

    @Published var nodes: [Node] = []
    @Published var edges: [Edge] = []
    @Published var position: [Int: CGPoint] = [:]
    @Published var suggestionPosition: [String: CGPoint] = [:]
    @Published var suggestions: [Suggestion] = []
    @Published var loadingSuggestions = false
    @Published var linkThreshold: Double = 2

    private var lastStore: [Int: Set<String>] = [:]

    func build(from store: Store) {
        let papers = store.papers.filter { !$0.stage.isExcluded }
        nodes = papers.map {
            Node(id: $0.id,
                 label: String($0.citeKey.prefix(18)),
                 refs: Set($0.references),
                 oaId: $0.openAlexId)
        }
        lastStore = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.refs) })

        // Two papers are linked when they cite the same works often enough to matter, or
        // when one directly cites the other.
        var out: [Edge] = []
        let idByOA = Dictionary(nodes.filter { !$0.oaId.isEmpty }.map { ($0.oaId, $0.id) },
                                uniquingKeysWith: { a, _ in a })
        for i in nodes.indices {
            for j in (i + 1)..<nodes.count {
                let a = nodes[i], b = nodes[j]
                var weight = a.refs.intersection(b.refs).count
                if !b.oaId.isEmpty && a.refs.contains(b.oaId) { weight += 4 }
                if !a.oaId.isEmpty && b.refs.contains(a.oaId) { weight += 4 }
                if weight >= Int(linkThreshold) { out.append(Edge(a: a.id, b: b.id, weight: weight)) }
            }
        }
        _ = idByOA
        edges = out
        relayout()
    }

    /// A small force-directed layout: linked papers pull together, everything pushes apart.
    /// Run to convergence once rather than animated, so the map is stable to read.
    func relayout() {
        guard !nodes.isEmpty else { position = [:]; return }
        var pos: [Int: CGPoint] = [:]
        let radius = 180.0 + Double(nodes.count) * 3
        for (i, n) in nodes.enumerated() {
            let angle = Double(i) / Double(nodes.count) * .pi * 2
            pos[n.id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }

        var adjacency: [Int: [(Int, Double)]] = [:]
        for e in edges {
            adjacency[e.a, default: []].append((e.b, Double(e.weight)))
            adjacency[e.b, default: []].append((e.a, Double(e.weight)))
        }

        let ids = nodes.map(\.id)
        for step in 0..<260 {
            let cooling = 1.0 - Double(step) / 260.0
            var force: [Int: CGVector] = [:]

            for i in ids.indices {
                for j in (i + 1)..<ids.count {
                    let a = ids[i], b = ids[j]
                    guard let pa = pos[a], let pb = pos[b] else { continue }
                    var dx = pa.x - pb.x, dy = pa.y - pb.y
                    var dist = sqrt(dx * dx + dy * dy)
                    if dist < 0.01 { dx = Double.random(in: -1...1); dy = Double.random(in: -1...1); dist = 1 }
                    let repel = 5200.0 / (dist * dist)
                    force[a, default: .zero].dx += dx / dist * repel
                    force[a, default: .zero].dy += dy / dist * repel
                    force[b, default: .zero].dx -= dx / dist * repel
                    force[b, default: .zero].dy -= dy / dist * repel
                }
            }

            for e in edges {
                guard let pa = pos[e.a], let pb = pos[e.b] else { continue }
                let dx = pb.x - pa.x, dy = pb.y - pa.y
                let dist = max(sqrt(dx * dx + dy * dy), 0.01)
                let pull = (dist - 120) * 0.012 * min(Double(e.weight), 6)
                force[e.a, default: .zero].dx += dx / dist * pull
                force[e.a, default: .zero].dy += dy / dist * pull
                force[e.b, default: .zero].dx -= dx / dist * pull
                force[e.b, default: .zero].dy -= dy / dist * pull
            }

            for id in ids {
                guard var p = pos[id] else { continue }
                let f = force[id] ?? .zero
                // Weak pull to the origin keeps unconnected papers from drifting off-screen.
                p.x += (f.dx - p.x * 0.004) * cooling * 0.6
                p.y += (f.dy - p.y * 0.004) * cooling * 0.6
                pos[id] = p
            }
        }
        position = pos
        layoutSuggestions()
    }

    private func layoutSuggestions() {
        var out: [String: CGPoint] = [:]
        let ring = 260.0 + Double(nodes.count) * 3
        for (i, s) in suggestions.enumerated() {
            let angle = Double(i) / Double(max(suggestions.count, 1)) * .pi * 2 + 0.3
            out[s.openAlexId] = CGPoint(x: cos(angle) * ring, y: sin(angle) * ring)
        }
        suggestionPosition = out
    }

    /// Counts every work your papers cite, drops the ones already in the library, and looks
    /// up the most-cited remainder. These are the papers your own corpus keeps pointing at.
    func findSuggestions(store: Store) async {
        loadingSuggestions = true
        defer { loadingSuggestions = false }

        let mine = Set(store.papers.compactMap { $0.openAlexId.isEmpty ? nil : $0.openAlexId })
        var tally: [String: Int] = [:]
        for p in store.papers where !p.stage.isExcluded {
            for r in p.references where !mine.contains(r) { tally[r, default: 0] += 1 }
        }
        let top = tally.filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(40)
        guard !top.isEmpty else {
            suggestions = []
            layoutSuggestions()
            store.flash("No repeated citations yet — add a few more OpenAlex records first")
            return
        }

        var found: [Suggestion] = []
        // OpenAlex takes up to 50 ids in one filter, so this is a couple of requests at most.
        for chunk in Array(top).chunked(into: 25) {
            let ids = chunk.map(\.key).joined(separator: "|")
            guard let url = URL(string: "https://api.openalex.org/works?filter=openalex_id:\(ids)&per-page=25"),
                  let root = try? await Net.json(url) as? [String: Any],
                  let results = root["results"] as? [Any] else { continue }
            for item in results {
                guard let w = item as? [String: Any],
                      let title = w["display_name"] as? String else { continue }
                let oa = ((w["id"] as? String) ?? "")
                    .replacingOccurrences(of: "https://openalex.org/", with: "")
                let count = tally[oa] ?? chunk.first { $0.key == oa }?.value ?? 0
                found.append(Suggestion(
                    openAlexId: oa,
                    title: title,
                    authors: (w["authorships"] as? [Any] ?? []).compactMap {
                        (($0 as? [String: Any])?["author"] as? [String: Any])?["display_name"] as? String
                    },
                    year: w["publication_year"] as? Int,
                    doi: ((w["doi"] as? String) ?? "")
                        .replacingOccurrences(of: "https://doi.org/", with: "").lowercased(),
                    citedByMine: count))
            }
        }
        suggestions = found.sorted { $0.citedByMine > $1.citedByMine }
        layoutSuggestions()
        store.flash(found.isEmpty ? "Nothing new found"
                                  : "Found \(found.count) works your papers cite but you haven't read")
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Side panels

struct MapDetail: View {
    let paper: Paper
    @ObservedObject var graph: GraphModel
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator

    private var neighbours: [(Paper, Int)] {
        graph.edges.compactMap { e -> (Paper, Int)? in
            let otherId = e.a == paper.id ? e.b : (e.b == paper.id ? e.a : nil)
            guard let otherId, let p = store.paper(otherId) else { return nil }
            return (p, e.weight)
        }
        .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: D.s4) {
                VStack(alignment: .leading, spacing: 4) {
                    StageBadge(stage: paper.stage)
                    Text(paper.title).font(D.heading)
                    Text("\(paper.authorLine) · \(paper.year.map(String.init) ?? "n.d.")")
                        .font(D.small).foregroundStyle(.secondary)
                }
                Button { nav.read(paper.id) } label: {
                    Label("Open in reader", systemImage: "book.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if !paper.references.isEmpty {
                    Text("\(paper.references.count) works cited")
                        .font(D.small).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: D.s2) {
                    SectionLabel(text: "Most connected to")
                    if neighbours.isEmpty {
                        Text("No shared references with anything else in the review yet.")
                            .font(D.small).foregroundStyle(.tertiary)
                    }
                    ForEach(neighbours.prefix(12), id: \.0.id) { other, weight in
                        Button { nav.read(other.id) } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(weight)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .frame(width: 20)
                                    .foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(other.title).font(D.small).lineLimit(2)
                                    Text(other.authorLine).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(D.s4)
        }
        .background(D.raised)
    }
}

struct SuggestionPanel: View {
    @ObservedObject var graph: GraphModel
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: D.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("What you're missing").font(D.heading)
                    Text("Works cited by two or more of your papers that aren't in your library. The number is how many of your papers cite it.")
                        .font(D.small).foregroundStyle(.secondary)
                }
                if graph.suggestions.isEmpty {
                    Text("Press “Find what I'm missing” above.")
                        .font(D.small).foregroundStyle(.tertiary)
                }
                ForEach(graph.suggestions) { s in
                    Card(padding: D.s3) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Chip(text: "cited by \(s.citedByMine) of yours", color: Palette.violet)
                                Spacer()
                                if let y = s.year { Text(String(y)).font(D.small).foregroundStyle(.secondary) }
                            }
                            Text(s.title).font(D.small.weight(.medium)).lineLimit(3)
                            Text(s.authors.prefix(3).joined(separator: ", "))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            HStack {
                                Button("Add to review") {
                                    let hit = SearchHit(
                                        id: s.openAlexId, title: s.title, authors: s.authors,
                                        year: s.year, venue: "", doi: s.doi, abstract: "",
                                        url: s.doi.isEmpty ? "" : "https://doi.org/\(s.doi)",
                                        pdfURL: "", provider: "OpenAlex (map suggestion)",
                                        oaStatus: "", citedBy: 0)
                                    if store.addPaper(from: hit, query: "Found via the map") != nil {
                                        store.reloadPapers()
                                        graph.suggestions.removeAll { $0.openAlexId == s.openAlexId }
                                        store.flash("Added to the review")
                                    } else {
                                        store.flash("Already in this review")
                                    }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                if !s.doi.isEmpty {
                                    Button { SafeLink.open("https://doi.org/\(s.doi)") }
                                        label: { Image(systemName: "arrow.up.forward.square") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(D.s4)
        }
        .background(D.raised)
    }
}
