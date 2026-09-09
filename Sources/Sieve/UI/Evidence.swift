import SwiftUI
import AppKit

/// Every highlight from every paper in one place. This is where the review stops being
/// a pile of PDFs and becomes a body of tagged, sourced information you can reason over.
struct EvidenceView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var nav: Navigator

    @State private var search = ""
    @State private var tagFilter: Set<Int> = []
    @State private var paperFilter: Int? = nil
    @State private var grouping: Grouping = .stance
    @State private var askText = ""
    @State private var answer: String? = nil
    @State private var showAsk = false
    @State private var stanceFilter: Set<Stance> = []
    @State private var verificationFilter: Set<Verification> = []

    enum Grouping: String, CaseIterable, Identifiable {
        case stance = "Evidence / thinking", tag = "By category", paper = "By paper", none = "Flat list"
        var id: String { rawValue }
    }

    private var items: [Evidence] {
        store.evidence.filter { e in
            (stanceFilter.isEmpty || stanceFilter.contains(e.stance))
            && (verificationFilter.isEmpty || verificationFilter.contains(e.verification))
            && (tagFilter.isEmpty || !tagFilter.isDisjoint(with: Set(e.tagIds)))
            && (paperFilter == nil || e.paperId == paperFilter!)
            && (search.isEmpty
                || e.quote.localizedCaseInsensitiveContains(search)
                || e.note.localizedCaseInsensitiveContains(search)
                || (store.paper(e.paperId)?.title.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            tagStrip
            Divider()
            if store.evidence.isEmpty {
                EmptyState(icon: "highlighter",
                           title: "No evidence extracted yet",
                           message: "Open a paper in the Reader, select a passage and press a colour. Each highlight lands here with its page, its category, its source database and the paper it came from.",
                           action: ("Open the reader", { nav.section = .reader }))
            } else if items.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "Nothing matches",
                           message: "\(store.evidence.count) highlights exist — loosen the filters.")
            } else {
                board
            }
        }
        .background(D.canvas)
        .sheet(isPresented: $showAsk) { askSheet }
    }

    private var toolbar: some View {
        Toolbar {
            SearchField(placeholder: "Search inside your highlights", text: $search)
                .frame(maxWidth: 320)
            Picker("", selection: $grouping) {
                ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 330)
            Menu {
                Button("All papers") { paperFilter = nil }
                Divider()
                ForEach(store.papers.filter { p in store.evidence.contains { $0.paperId == p.id } }) { p in
                    Button("\(p.citeKey) — \(p.title.prefix(50))") { paperFilter = p.id }
                }
            } label: {
                Label(paperFilter.flatMap { store.paper($0)?.citeKey } ?? "All papers", systemImage: "doc.text")
            }
            .frame(width: 160)
            Spacer()
            UndoRedoButtons(history: store.history, store: store)
            Text("\(items.count) of \(store.evidence.count)").font(D.small).foregroundStyle(.secondary)
            if Assistant.isAvailable && assistant.enabled {
                Button { showAsk = true } label: { Label("Ask across papers", systemImage: "sparkle") }
                    .help("Ask a question and get an answer built only from your own highlights, with citations")
            }
            Menu {
                Button("Visible highlights as Markdown") { Exporters.exportEvidenceMarkdown(store, items) }
                Button("Visible highlights as CSV") { Exporters.exportEvidenceCSV(store, items) }
                Button("Visible highlights as Excel") {
                    Exporters.save(data: XLSX.build(grid: Exporters.evidenceGrid(store, items),
                                                    sheetName: "Highlights"),
                                   suggested: "highlights.xlsx", store: store)
                }
                Divider()
                Button("Everything in one folder…") { Exporters.exportEverything(store) }
                Button("Full review report as PDF") { Exporters.exportReportPDF(store) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .frame(width: 100)
        }
    }

    /// Filter by colour. Because the colours mean the same thing here as in the PDF,
    /// finding "everything I marked as a Gap" is one click.
    private var tagStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Stance.allCases) { st in
                    let n = store.evidence.filter { $0.stance == st }.count
                    Button {
                        if stanceFilter.contains(st) { stanceFilter.remove(st) } else { stanceFilter.insert(st) }
                    } label: {
                        Chip(text: "\(st.label)\(n > 0 ? " \(n)" : "")", color: st.color,
                             filled: stanceFilter.contains(st), icon: st.icon)
                    }
                    .buttonStyle(.plain).opacity(n == 0 ? 0.45 : 1)
                    .help(st.blurb)
                }
                ForEach([Verification.verified, .conflicting], id: \.self) { v in
                    let n = store.evidence.filter { $0.verification == v }.count
                    if n > 0 {
                        Button {
                            if verificationFilter.contains(v) { verificationFilter.remove(v) }
                            else { verificationFilter.insert(v) }
                        } label: {
                            Chip(text: "\(v.label) \(n)", color: v.color,
                                 filled: verificationFilter.contains(v), icon: v.icon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider().frame(height: 16)
                Button {
                    tagFilter = []
                } label: {
                    Chip(text: "All", color: Palette.slate, filled: tagFilter.isEmpty)
                }
                .buttonStyle(.plain)

                ForEach(store.tags) { t in
                    let n = store.evidenceCount(forTag: t.id)
                    Button {
                        if tagFilter.contains(t.id) { tagFilter.remove(t.id) } else { tagFilter.insert(t.id) }
                    } label: {
                        Chip(text: "\(t.name)\(n > 0 ? " \(n)" : "")",
                             color: t.color,
                             filled: tagFilter.contains(t.id))
                    }
                    .buttonStyle(.plain)
                    .opacity(n == 0 ? 0.45 : 1)
                }
            }
            .padding(.horizontal, D.s4).padding(.vertical, D.s2)
        }
        .background(D.surface)
    }

    private var board: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: D.s4, pinnedViews: [.sectionHeaders]) {
                switch grouping {
                case .stance:
                    // The most important split in the app: what the sources say, what you
                    // think they mean, and what you still don't know.
                    ForEach(Stance.allCases) { st in
                        let group = items.filter { $0.stance == st }
                        if !group.isEmpty {
                            self.group(title: st.label, tint: st.color, subtitle: st.blurb, items: group)
                        }
                    }
                case .tag:
                    ForEach(store.tags.filter { t in items.contains { $0.tagIds.contains(t.id) } }) { t in
                        group(title: t.name, tint: t.color, subtitle: t.detail,
                              items: items.filter { $0.tagIds.contains(t.id) })
                    }
                    let untagged = items.filter { $0.tagIds.isEmpty }
                    if !untagged.isEmpty {
                        group(title: "Untagged", tint: Palette.slate, subtitle: "", items: untagged)
                    }
                case .paper:
                    ForEach(store.papers.filter { p in items.contains { $0.paperId == p.id } }) { p in
                        group(title: p.title, tint: Palette.accent,
                              subtitle: "\(p.authorLine) · \(p.year.map(String.init) ?? "n.d.") · \(p.sourceDB)",
                              items: items.filter { $0.paperId == p.id })
                    }
                case .none:
                    columns(items)
                }
            }
            .padding(D.s4)
        }
    }

    private func group(title: String, tint: Color, subtitle: String, items: [Evidence]) -> some View {
        VStack(alignment: .leading, spacing: D.s2) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 16)
                Text(title).font(D.heading).lineLimit(1)
                Text("\(items.count)").font(D.small).foregroundStyle(.secondary)
                if !subtitle.isEmpty {
                    Text("— \(subtitle)").font(D.small).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            columns(items)
        }
    }

    /// A masonry-ish three-column layout: evidence cards are short and read better
    /// side by side than in one long ribbon.
    private func columns(_ items: [Evidence]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: D.s3)],
                  alignment: .leading, spacing: D.s3) {
            ForEach(items) { e in
                EvidenceCard(evidence: e, paper: store.paper(e.paperId), compact: false) {
                    nav.read(e.paperId)
                }
            }
        }
    }

    // MARK: Ask across the corpus

    private var askSheet: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Text("Ask your own highlights").font(D.title)
            Text("Claude answers using only the \(items.count) highlights currently visible — nothing from outside your corpus. Every claim is cited back to a paper and page.")
                .font(D.small).foregroundStyle(.secondary)

            TextField("e.g. Where do these papers disagree about tactile feedback latency?",
                      text: $askText, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(3, reservesSpace: true)

            if assistant.busy { HStack { ProgressView().controlSize(.small); Text("Reading your highlights…").font(D.small) } }

            if let answer {
                ScrollView {
                    Text(answer).font(D.serif).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 280)
                .padding(D.s3).background(D.surface)
                .clipShape(RoundedRectangle(cornerRadius: D.radius))
            }

            HStack {
                if answer != nil {
                    Button("Copy answer") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer!, forType: .string)
                    }
                }
                Spacer()
                Button("Close") { showAsk = false }
                Button("Ask") {
                    Task {
                        await assistant.detectModel()
                        answer = await assistant.askCorpus(question: askText, evidence: items,
                                                           papers: store.papers, tags: store.tags)
                        if let a = answer {
                            store.logAI(kind: .askCorpus, model: assistant.lastModel,
                                        subjectKind: "project", subjectId: store.currentProjectId,
                                        asked: askText, said: a)
                        } else { answer = assistant.lastError }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(askText.isEmpty || assistant.busy)
            }
        }
        .padding(D.s5).frame(width: 660)
    }
}
