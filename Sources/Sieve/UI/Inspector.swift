import SwiftUI
import AppKit

/// The right-hand panel in the reader: what this paper is, where it came from,
/// and every piece of evidence you've pulled out of it.
struct InspectorPanel: View {
    let paper: Paper?
    @ObservedObject var controller: PDFController
    @EnvironmentObject var store: Store
    @EnvironmentObject var assistant: Assistant
    @State private var tab = 0
    @State private var editingNote: Int? = nil
    @State private var noteDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Highlights").tag(0)
                Text("Paper").tag(1)
                Text("Decision").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(D.s3)
            Divider()
            if let p = paper {
                switch tab {
                case 0: highlights(p)
                case 1: ScrollView { paperDetail(p).padding(D.s4) }
                default: ScrollView { decision(p).padding(D.s4) }
                }
            } else {
                EmptyState(icon: "sidebar.right", title: "No paper open", message: "Pick a paper on the left.")
            }
        }
        .background(D.raised)
    }

    // MARK: Highlights

    private func highlights(_ p: Paper) -> some View {
        let items = store.evidence(forPaper: p.id)
        return Group {
            if items.isEmpty {
                EmptyState(icon: "highlighter",
                           title: "No highlights yet",
                           message: "Select text in the PDF and click a colour above — or press its number key. Each highlight is stored with its page, its colour category, and the paper it came from.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: D.s2) {
                        HStack {
                            Text("\(items.count) highlight\(items.count == 1 ? "" : "s")")
                                .font(D.small).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button("Copy all as quotes") { copyAll(items, p) }
                                Button("Copy as Markdown") { copyMarkdown(items, p) }
                            } label: { Image(systemName: "square.and.arrow.up") }
                                .menuStyle(.borderlessButton).frame(width: 28)
                        }
                        ForEach(items) { e in
                            EvidenceCard(evidence: e, paper: p, compact: true) {
                                controller.reveal(e)
                            }
                        }
                    }
                    .padding(D.s3)
                }
            }
        }
    }

    private func copyAll(_ items: [Evidence], _ p: Paper) {
        let text = items.map { "“\($0.quote)” (\(p.citeKey), p.\($0.page + 1))" }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        store.flash("Copied \(items.count) quotes")
    }

    private func copyMarkdown(_ items: [Evidence], _ p: Paper) {
        var out = "## \(p.title)\n\(p.reference)\n\n"
        let grouped = Dictionary(grouping: items) { e in
            e.tagIds.compactMap { store.tag($0)?.name }.sorted().joined(separator: ", ")
        }
        for (tagName, group) in grouped.sorted(by: { $0.key < $1.key }) {
            out += "### \(tagName.isEmpty ? "Untagged" : tagName)\n"
            for e in group {
                out += "- “\(e.quote)” (p.\(e.page + 1))\n"
                if !e.note.isEmpty { out += "  - \(e.note)\n" }
            }
            out += "\n"
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(out, forType: .string)
        store.flash("Copied as Markdown")
    }

    // MARK: Paper detail + provenance

    private func paperDetail(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: D.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.title).font(D.heading).textSelection(.enabled)
                Text(p.authorLine).font(D.body).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let y = p.year { Chip(text: String(y), color: Palette.slate) }
                    if !p.venue.isEmpty { Text(p.venue).font(D.small).foregroundStyle(.secondary).lineLimit(2) }
                }
            }

            // Provenance block — the whole reason evidence is trustworthy later.
            Card(padding: D.s3) {
                VStack(alignment: .leading, spacing: D.s2) {
                    SectionLabel(text: "Where this came from")
                    kv("Database", p.sourceDB.isEmpty ? "—" : p.sourceDB)
                    if !p.sourceQuery.isEmpty { kv("Found by search", p.sourceQuery) }
                    kv("Added to review", p.addedAt.formatted(date: .abbreviated, time: .shortened))
                    if let a = p.accessedAt { kv("PDF retrieved", a.formatted(date: .abbreviated, time: .shortened)) }
                    if !p.doi.isEmpty {
                        HStack(spacing: 4) {
                            Text("DOI").font(D.small).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
                            Link(p.doi, destination: URL(string: "https://doi.org/\(p.doi)")!)
                                .font(D.mono).lineLimit(1)
                        }
                    }
                    if !p.url.isEmpty, let u = URL(string: p.url.hasPrefix("http") ? p.url : "https://doi.org/\(p.doi)") {
                        HStack(spacing: 4) {
                            Text("Source link").font(D.small).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
                            Link(u.host ?? p.url, destination: u).font(D.small).lineLimit(1)
                        }
                    }
                    if !p.oaStatus.isEmpty { kv("Open access", p.oaStatus) }
                    if !p.sdgs.isEmpty { kv("SDG", p.sdgs.joined(separator: ", ")) }
                    if !p.pubDate.isEmpty { kv("Published", p.pubDate) }
                    if p.citedBy > 0 { kv("Cited by", "\(p.citedBy)") }
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p.reference, forType: .string)
                store.flash("Reference copied")
            } label: { Label("Copy reference", systemImage: "quote.opening") }
                .buttonStyle(.bordered)

            if !p.abstract.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Abstract")
                    Text(p.abstract).font(D.serif).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            field("Conclusion — what this paper concludes",
                  binding: Binding(get: { p.conclusion },
                                   set: { var q = p; q.conclusion = $0; store.updatePaper(q) }),
                  height: 90)
            field("What I still need to read in it",
                  binding: Binding(get: { p.toRead },
                                   set: { var q = p; q.toRead = $0; store.updatePaper(q) }),
                  height: 60)
            field("My notes on this paper",
                  binding: Binding(get: { p.notes },
                                   set: { var q = p; q.notes = $0; store.updatePaper(q) }),
                  height: 90)
        }
    }

    private func field(_ label: String, binding: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            TextEditor(text: binding)
                .font(D.body)
                .frame(minHeight: height)
                .padding(4)
                .background(D.surface)
                .clipShape(RoundedRectangle(cornerRadius: D.radius))
                .hairlineBorder()
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(k).font(D.small).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            Text(v).font(D.small).textSelection(.enabled)
        }
    }

    // MARK: Screening decision, right where you're reading

    private func decision(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: D.s4) {
            VStack(alignment: .leading, spacing: D.s2) {
                SectionLabel(text: "Current stage")
                StageBadge(stage: p.stage)
                if !p.excludeReason.isEmpty {
                    Text(p.excludeReason).font(D.small).foregroundStyle(.secondary)
                }
            }

            if let proj = store.project, !proj.inclusionCriteria.isEmpty || !proj.exclusionCriteria.isEmpty {
                Card(padding: D.s3) {
                    VStack(alignment: .leading, spacing: D.s2) {
                        if !proj.inclusionCriteria.isEmpty {
                            SectionLabel(text: "Include if")
                            Text(proj.inclusionCriteria).font(D.small)
                        }
                        if !proj.exclusionCriteria.isEmpty {
                            SectionLabel(text: "Exclude if")
                            Text(proj.exclusionCriteria).font(D.small)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: D.s2) {
                SectionLabel(text: "Full-text decision")
                Button {
                    store.setStage(p.id, .included)
                    store.flash("Included in the review")
                } label: { Label("Include in review", systemImage: "checkmark.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Palette.emerald)

                ExcludeButton(paper: p, stage: .excludedEligibility)
                Button("Send back to screening") { store.setStage(p.id, .screening) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// Excluding a paper without a reason breaks the PRISMA flow diagram, so the reason
/// is part of the action rather than an afterthought.
struct ExcludeButton: View {
    let paper: Paper
    let stage: Stage
    @EnvironmentObject var store: Store
    @State private var showing = false
    @State private var reason = ""

    static let commonReasons = [
        "Wrong population", "Wrong intervention", "Wrong outcome", "Wrong study design",
        "Not peer reviewed", "Not in English", "Outside date range", "Duplicate data",
        "No full text available", "Off topic"
    ]

    var body: some View {
        Button(role: .destructive) { showing = true } label: {
            Label("Exclude…", systemImage: "xmark.circle").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: D.s3) {
                Text("Why is this excluded?").font(D.heading)
                Text("PRISMA requires a reason for every full-text exclusion. It goes straight into your flow diagram.")
                    .font(D.small).foregroundStyle(.secondary).frame(width: 300)
                ForEach(Self.commonReasons, id: \.self) { r in
                    Button(r) {
                        store.setStage(paper.id, stage, reason: r)
                        showing = false
                        store.flash("Excluded — \(r)")
                    }
                    .buttonStyle(.plain).font(D.body)
                }
                Divider()
                HStack {
                    TextField("Other reason…", text: $reason)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commit() }
                    Button("Exclude") { commit() }.disabled(reason.isEmpty)
                }
            }
            .padding(D.s4)
            .frame(width: 340)
        }
    }

    private func commit() {
        guard !reason.isEmpty else { return }
        store.setStage(paper.id, stage, reason: reason)
        showing = false
        store.flash("Excluded — \(reason)")
        reason = ""
    }
}

// MARK: - Evidence card, reused in the inspector and the Evidence board

struct EvidenceCard: View {
    let evidence: Evidence
    let paper: Paper?
    var compact = false
    var onJump: (() -> Void)? = nil

    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @State private var editing = false
    @State private var noteDraft = ""
    @State private var quoteDraft = ""
    @State private var relating = false

    private var tags: [Tag] { evidence.tagIds.compactMap { store.tag($0) } }
    private var links: [Relation] { store.relations(for: .evidence, evidence.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            HStack(spacing: 5) {
                // Stance first: what the source says, what you think, and what you don't know
                // must never look the same.
                Chip(text: evidence.stance.label, color: evidence.stance.color,
                     filled: evidence.stance != .evidence, icon: evidence.stance.icon)
                if evidence.kind != .quote {
                    Chip(text: evidence.kind.label, color: Palette.slate, icon: evidence.kind.icon)
                }
                ForEach(tags) { t in Chip(text: t.name, color: t.color) }
                if evidence.aiGenerated { AIBadge() }
                Spacer()
                if evidence.page >= 0 {
                    Text("p.\(evidence.page + 1)").font(D.mono).foregroundStyle(.tertiary)
                }
                Button {
                    store.deleteEvidence(evidence.id)
                    store.flash("Highlight removed")
                } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary.opacity(0.55))
                .help("Delete this highlight — it disappears from the PDF too")

                Menu {
                    if evidence.hasLocation {
                        Button("Jump to it in the PDF") {
                            if let onJump { onJump() } else if let p = paper { nav.read(p.id) }
                        }
                    }
                    Button("Edit note") { noteDraft = evidence.note; quoteDraft = evidence.quote; editing = true }
                    Button("Link to other evidence…") { relating = true }
                    Divider()
                    Menu("This is") {
                        ForEach(Stance.allCases) { st in
                            Button(st == evidence.stance ? "✓ \(st.label)" : st.label) {
                                var e = evidence; e.stance = st; store.updateEvidence(e)
                            }
                        }
                    }
                    Menu("Kind") {
                        ForEach(EvidenceKind.allCases) { k in
                            Button(k == evidence.kind ? "✓ \(k.label)" : k.label) {
                                var e = evidence; e.kind = k; store.updateEvidence(e)
                            }
                        }
                    }
                    Menu("Confidence") {
                        ForEach(Confidence.allCases) { c in
                            Button(c == evidence.confidence ? "✓ \(c.label)" : c.label) {
                                var e = evidence; e.confidence = c; store.updateEvidence(e)
                            }
                        }
                    }
                    Menu("Status") {
                        ForEach(Verification.allCases) { v in
                            Button(v == evidence.verification ? "✓ \(v.label)" : v.label) {
                                var e = evidence; e.verification = v; store.updateEvidence(e)
                            }
                        }
                    }
                    Menu("Change category") {
                        ForEach(store.categoryTags) { t in
                            Button(t.name) {
                                var e = evidence; e.tagIds = [t.id]; e.colorHex = t.colorHex
                                store.updateEvidence(e)
                            }
                        }
                    }
                    Menu("Add data type") {
                        ForEach(store.dataTypeTags) { t in
                            Button(t.name) {
                                var e = evidence
                                if !e.tagIds.contains(t.id) { e.tagIds.append(t.id) }
                                store.updateEvidence(e)
                            }
                        }
                    }
                    Button("Copy quote") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("“\(evidence.quote)” (\(paper?.citeKey ?? ""), p.\(evidence.page + 1))",
                                                       forType: .string)
                    }
                    Divider()
                    Button("Delete", role: .destructive) { store.deleteEvidence(evidence.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 22)
            }

            Text(evidence.quote)
                .font(D.serif)
                .lineLimit(compact ? 6 : nil)
                .textSelection(.enabled)
                .padding(.leading, D.s2)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(hex: evidence.colorHex)).frame(width: 3)
                }

            if !evidence.note.isEmpty {
                Text(evidence.note)
                    .font(D.small)
                    .foregroundStyle(.secondary)
                    .padding(.leading, D.s2)
            }

            // Typed links are what turn highlights into an argument.
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(links) { r in
                        let outgoing = r.fromId == evidence.id && r.fromKind == NodeKind.evidence.rawValue
                        let otherId = outgoing ? r.toId : r.fromId
                        let other = store.evidence(otherId)
                        HStack(spacing: 4) {
                            Image(systemName: r.relation.icon).font(.system(size: 9))
                                .foregroundStyle(r.relation.color)
                            Text(outgoing ? r.relation.label : "\(r.relation.label) ←")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(r.relation.color)
                            Text(other.map { String($0.quote.prefix(52)) } ?? "a source")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button { store.deleteRelation(r.id) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.leading, D.s2)
            }

            // Confidence and verification only show once they've been set away from default,
            // so an untouched highlight stays quiet.
            if evidence.verification != .unchecked || evidence.confidence != .medium {
                HStack(spacing: 6) {
                    if evidence.verification != .unchecked {
                        Chip(text: evidence.verification.label, color: evidence.verification.color,
                             icon: evidence.verification.icon)
                    }
                    if evidence.confidence != .medium {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i < evidence.confidence.dots ? Palette.slate : Color.secondary.opacity(0.2))
                                    .frame(width: 5, height: 5)
                            }
                            Text("\(evidence.confidence.label) confidence")
                                .font(.system(size: 9.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, D.s2)
            }

            if !compact, let p = paper {
                HStack(spacing: 4) {
                    Text(p.authorLine).font(D.small)
                    if let y = p.year { Text("· \(String(y))").font(D.small) }
                    if !p.doi.isEmpty {
                        Text("·").font(D.small)
                        Link("doi", destination: URL(string: "https://doi.org/\(p.doi)")!).font(D.small)
                    }
                    Spacer()
                    Text(evidence.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(D.s3)
        .background(D.surface)
        .clipShape(RoundedRectangle(cornerRadius: D.radius))
        .hairlineBorder()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if let onJump { onJump() } }
        .sheet(isPresented: $relating) {
            RelationEditor(from: evidence) { relating = false }
        }
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: D.s3) {
                SectionLabel(text: "Quoted text")
                TextEditor(text: $quoteDraft).font(D.serif).frame(height: 90).hairlineBorder()
                SectionLabel(text: "My note — why this matters")
                TextEditor(text: $noteDraft).font(D.body).frame(height: 90).hairlineBorder()
                HStack {
                    Spacer()
                    Button("Cancel") { editing = false }
                    Button("Save") {
                        var e = evidence; e.note = noteDraft; e.quote = quoteDraft
                        store.updateEvidence(e); editing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(D.s4).frame(width: 420)
        }
    }
}

/// Links one piece of evidence to another with a typed relation. This is the step that turns
/// a collection of highlights into an argument you can inspect: which findings support a
/// claim, which sources contradict each other, what still rests on nothing.
struct RelationEditor: View {
    let from: Evidence
    var done: () -> Void
    @EnvironmentObject var store: Store
    @State private var type: RelationType = .supports
    @State private var search = ""
    @State private var note = ""
    @State private var target: Int? = nil

    private var candidates: [Evidence] {
        store.evidence
            .filter { $0.id != from.id }
            .filter { search.isEmpty
                || $0.quote.localizedCaseInsensitiveContains(search)
                || (store.paper($0.paperId)?.title.localizedCaseInsensitiveContains(search) ?? false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Text("Link this to other evidence").font(D.title)

            Card(padding: D.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Chip(text: from.stance.label, color: from.stance.color, icon: from.stance.icon)
                        if let p = store.paper(from.paperId) {
                            Text("\(p.citeKey), p.\(from.page + 1)").font(D.mono).foregroundStyle(.tertiary)
                        }
                    }
                    Text(from.quote).font(D.serif).lineLimit(3)
                }
            }

            HStack(spacing: 5) {
                Text("…").font(D.body).foregroundStyle(.secondary)
                Picker("", selection: $type) {
                    ForEach(RelationType.allCases.filter { $0 != .cites }) { r in
                        Text(r.label).tag(r)
                    }
                }
                .labelsHidden().frame(width: 160)
                Text("…").font(D.body).foregroundStyle(.secondary)
                Spacer()
            }

            SearchField(placeholder: "Find the other passage", text: $search)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates.prefix(60)) { e in
                        Button { target = e.id } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: target == e.id ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(target == e.id ? Palette.accent : Color.secondary.opacity(0.4))
                                Rectangle().fill(Color(hex: e.colorHex)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.quote).font(D.small).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    HStack(spacing: 4) {
                                        Chip(text: e.stance.label, color: e.stance.color)
                                        if let p = store.paper(e.paperId) {
                                            Text("\(p.citeKey) · p.\(e.page + 1)")
                                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            .padding(6)
                            .background(target == e.id ? Palette.accent.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 240)

            TextField("Why? (optional)", text: $note).textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Create link") {
                    guard let t = target else { return }
                    store.relate((.evidence, from.id), type, (.evidence, t), note: note)
                    store.flash("Linked — \(type.label)")
                    done()
                }
                .buttonStyle(.borderedProminent)
                .disabled(target == nil)
            }
        }
        .padding(D.s5).frame(width: 620)
    }
}
