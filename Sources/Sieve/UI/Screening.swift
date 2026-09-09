import SwiftUI
import AppKit

/// Title/abstract screening, full-text assessment, and a record of what you already decided.
/// Every decision is reversible: nothing here is a one-way door.
struct ScreeningView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var downloader: Downloader
    @EnvironmentObject var engine: SearchEngine
    @State private var mode: Mode = .titleAbstract
    @State private var selectedId: Int? = nil
    @State private var verdict: Assistant.ScreenVerdict? = nil
    @State private var autoScreening = false
    @State private var autoProgress = ""
    @State private var keyMonitor: Any? = nil
    @State private var showExclude = false
    @State private var customReason = ""
    @State private var filter = ""
    @AppStorage("sieve.screeningQueueWidth") private var queueWidth: Double = 300
    @AppStorage("sieve.screeningRailWidth") private var railWidth: Double = 260
    @State private var showShortcuts = false
    @AppStorage("sieve.highlightCriteria") private var highlightCriteria = true

    enum Mode: String, CaseIterable, Identifiable {
        case titleAbstract = "Title & abstract"
        case fullText = "Full text"
        case decided = "Decided"
        var id: String { rawValue }
    }

    private var queue: [Paper] {
        let base: [Paper]
        switch mode {
        case .titleAbstract: base = store.pendingScreening
        case .fullText:      base = store.pendingFullText
        case .decided:       base = store.decided
        }
        guard !filter.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(filter)
            || $0.authorLine.localizedCaseInsensitiveContains(filter)
            || $0.abstract.localizedCaseInsensitiveContains(filter)
        }
    }

    private var index: Int { queue.firstIndex { $0.id == selectedId } ?? 0 }
    private var current: Paper? {
        if let id = selectedId, let p = queue.first(where: { $0.id == id }) { return p }
        return queue.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if queue.isEmpty { emptyState } else {
                HStack(spacing: 0) {
                    queueList.frame(width: queueWidth)
                    PaneDivider(width: $queueWidth, range: 220...460)
                    detail.frame(maxWidth: .infinity)
                }
            }
        }
        .background(D.canvas)
        .onAppear { installKeys(); if selectedId == nil { selectedId = queue.first?.id } }
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }
        .onChange(of: mode) { _, _ in selectedId = queue.first?.id; verdict = nil }
        .sheet(isPresented: $showShortcuts) { ShortcutSheet { showShortcuts = false } }
        .onChange(of: selectedId) { _, _ in
            verdict = nil
            // Reading a PDF's sections costs milliseconds, so the conclusion is simply there
            // by the time you look at the record rather than needing to be asked for.
            if let p = current, p.hasPDF, p.extractedConclusion.isEmpty, p.conclusionHeading.isEmpty {
                extractSections(p)
            }
        }
        .onAppear {
            if let p = current, p.hasPDF, p.extractedConclusion.isEmpty, p.conclusionHeading.isEmpty {
                extractSections(p)
            }
        }
    }

    private var header: some View {
        Toolbar {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text("\(m.rawValue) \(count(m) > 0 ? "(\(count(m)))" : "")").tag(m)
                }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 380)

            SearchField(placeholder: "Filter this list", text: $filter).frame(width: 200)

            if mode != .decided, !queue.isEmpty {
                ProgressView(value: Double(index + 1), total: Double(queue.count))
                    .frame(width: 90)
                Text("\(index + 1) / \(queue.count)")
                    .font(D.small.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if Assistant.isAvailable && assistant.enabled && mode != .decided {
                Button { Task { await suggestForCurrent() } } label: { Label("Ask Claude", systemImage: "sparkle") }
                    .disabled(assistant.busy || current == nil)
                    .help("Claude checks this abstract against your criteria — you still decide")
                Button { Task { await autoScreenAll() } } label: {
                    if autoScreening { HStack { ProgressView().controlSize(.small); Text(autoProgress) } }
                    else { Label("Pre-screen all", systemImage: "wand.and.stars") }
                }
                .disabled(autoScreening || queue.isEmpty)
                .help("Leaves a recommendation on every record. Nothing is decided for you.")
            }
        }
    }

    private func count(_ m: Mode) -> Int {
        switch m {
        case .titleAbstract: return store.pendingScreening.count
        case .fullText: return store.pendingFullText.count
        case .decided: return store.decided.count
        }
    }

    private var emptyState: some View {
        EmptyState(
            icon: mode == .decided ? "clock.arrow.circlepath" : "checkmark.circle",
            title: mode == .decided ? "Nothing decided yet"
                 : mode == .titleAbstract ? "Screening queue is clear" : "No full texts waiting",
            message: mode == .decided
                ? "Once you include or exclude records they collect here, and any decision can be taken back."
                : mode == .titleAbstract
                ? "Every record has been triaged. \(store.pendingFullText.count) papers are waiting for full-text assessment."
                : "Read the included papers, or go back to title/abstract screening.",
            action: mode == .titleAbstract && !store.pendingFullText.isEmpty
                ? ("Go to full text", { mode = .fullText })
                : ("See the PRISMA flow", { nav.section = .prisma }))
    }

    // MARK: Left — the list

    private var queueList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedId) {
                ForEach(queue) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).font(D.small.weight(.medium)).lineLimit(2)
                        HStack(spacing: 4) {
                            Text("\(p.authorLine) · \(p.year.map(String.init) ?? "n.d.")")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            if p.hasPDF { Image(systemName: "doc.fill").font(.system(size: 8)).foregroundStyle(Palette.emerald) }
                        }
                        if mode == .decided {
                            HStack(spacing: 4) {
                                StageBadge(stage: p.stage)
                                if !p.excludeReason.isEmpty {
                                    Text(p.excludeReason).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(p.id)
                    .id(p.id)
                }
            }
            .listStyle(.inset)
            .onChange(of: selectedId) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    // MARK: Right — the record

    @ViewBuilder
    private var detail: some View {
        if let p = current {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: D.s4) {
                        heading(p)
                        if let proj = store.project,
                           !proj.inclusionCriteria.isEmpty || !proj.exclusionCriteria.isEmpty {
                            HStack(alignment: .top, spacing: D.s3) {
                                criteriaCard("Include if", proj.inclusionCriteria, Palette.emerald)
                                criteriaCard("Exclude if", proj.exclusionCriteria, Palette.rose)
                            }
                        }
                        if let v = verdict { verdictCard(v) }
                        keywordsBlock(p)
                        abstractBlock(p)
                        conclusionBlock(p)
                        notesBlock(p)
                    }
                    .padding(D.s5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                PaneDivider(width: $railWidth, range: 220...340, sizesTrailingPane: true)

                // The decision never scrolls away. Screening is hundreds of repetitions of
                // the same two choices, so the choices stay pinned where the hand already is.
                decisionRail(p)
                    .frame(width: railWidth)
            }
        } else {
            EmptyState(icon: "doc.text", title: "Nothing selected", message: "Pick a record on the left.")
        }
    }

    // MARK: The decision rail

    private func decisionRail(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: D.s4) {
                    progressBlock
                    if mode == .decided { decidedActions(p) } else { activeActions(p) }
                    navBlock
                    fullTextBlock(p)
                }
                .padding(D.s3)
            }
            Divider()
            shortcutFooter
        }
        .background(D.raised)
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(index + 1) of \(queue.count)")
                    .font(D.small.monospacedDigit().weight(.medium))
                Spacer()
                if mode != .decided {
                    Text("\(queue.count) left").font(D.small).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(index + 1), total: Double(max(queue.count, 1)))
                .progressViewStyle(.linear)
        }
    }

    /// Include and exclude, both full width and unmissable, with every exclusion reason
    /// already on screen — no popover, no second click to find out what the options are.
    private func activeActions(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Button {
                decide(mode == .titleAbstract ? .sought : .included)
            } label: {
                VStack(spacing: 2) {
                    Label(mode == .titleAbstract ? "Keep" : "Include", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(mode == .titleAbstract ? "get the full text" : "into the review")
                        .font(.system(size: 10)).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.emerald)
            .keyboardShortcut("f", modifiers: [])
            .help("Keep this record — F")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        .foregroundStyle(Palette.rose)
                    Text("EXCLUDE — PICK A REASON")
                        .font(.system(size: 9.5, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Palette.rose)
                }
                Text("PRISMA needs a reason for every exclusion.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)

                ForEach(Array(ExcludeButton.commonReasons.enumerated()), id: \.offset) { i, reason in
                    Button {
                        decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility,
                               reason: reason)
                    } label: {
                        HStack(spacing: 6) {
                            Text(i < 9 ? "\(i + 1)" : " ")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .frame(width: 13, height: 13)
                                .background(Palette.rose.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(Palette.rose)
                            Text(reason).font(D.small).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.rose.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(i < 9 ? "Exclude — \(reason)  (press \(i + 1))" : "Exclude — \(reason)")
                }

                HStack(spacing: 4) {
                    TextField("Other reason…", text: $customReason)
                        .textFieldStyle(.roundedBorder).font(D.small)
                        .onSubmit { commitCustom() }
                    Button {
                        commitCustom()
                    } label: { Image(systemName: "arrow.right.circle.fill") }
                        .buttonStyle(.plain)
                        .disabled(customReason.isEmpty)
                        .foregroundStyle(customReason.isEmpty ? Color.secondary.opacity(0.4) : Palette.rose)
                }
            }
        }
    }

    private func decidedActions(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: D.s3) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Current decision")
                StageBadge(stage: p.stage)
                if !p.excludeReason.isEmpty {
                    Text(p.excludeReason).font(D.small).foregroundStyle(.secondary)
                }
            }
            Button {
                store.setStage(p.id, .screening, reason: "")
                store.flash("Back in the screening queue")
            } label: {
                Label("Undo this decision", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.bordered)

            if p.stage == .included {
                Button {
                    decide(.excludedEligibility, reason: "Reconsidered after inclusion")
                } label: {
                    Label("Exclude instead", systemImage: "xmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.bordered).tint(Palette.rose)
            } else {
                Button {
                    decide(.included, reason: "")
                } label: {
                    Label("Include instead", systemImage: "checkmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(Palette.emerald)
            }
        }
    }

    private var navBlock: some View {
        HStack(spacing: 5) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").frame(maxWidth: .infinity).padding(.vertical, 3)
            }
            .disabled(index == 0).help("Previous — K or ←")
            Button { step(1) } label: {
                Label("Skip", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
            }
            .disabled(index >= queue.count - 1).help("Next without deciding — J or →")
        }
        .buttonStyle(.bordered)
    }

    /// The full-text status, stated as fact rather than intention: a verified PDF on disk,
    /// or an honest account of what is missing.
    private func fullTextBlock(_ p: Paper) -> some View {
        let proof = p.pdfProof
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Full text")
            if proof.retrieved {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.emerald)
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PDF verified").font(D.small.weight(.medium))
                        Text("\(proof.pages) pages · \(proof.sizeText)")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Button { nav.read(p.id) } label: {
                    Label("Read", systemImage: "book.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.bordered).help("Open in the reader — R")
                Button { extractSections(p) } label: {
                    Label("Re-read the PDF", systemImage: "doc.text.magnifyingglass")
                        .font(D.small).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            } else if p.pdfBroken {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.rose)
                    Text("The attached file can't be read").font(D.small).foregroundStyle(Palette.rose)
                }
                Text("Moved, deleted, or not a real PDF. PRISMA counts this as not retrieved.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                fetchButton(p)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "doc.badge.plus").foregroundStyle(.secondary)
                    Text("No PDF yet").font(D.small).foregroundStyle(.secondary)
                }
                if store.strictRetrieval {
                    Text("Without one this can't count as retrieved in PRISMA.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                fetchButton(p)
            }
        }
        .padding(D.s2 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(D.surface)
        .clipShape(RoundedRectangle(cornerRadius: D.radius))
        .hairlineBorder()
    }

    private func fetchButton(_ p: Paper) -> some View {
        VStack(spacing: 4) {
            Button {
                Task { await downloader.fetch(paper: p, store: store, email: engine.contactEmail) }
            } label: {
                if downloader.active[p.id] != nil {
                    HStack(spacing: 4) { ProgressView().controlSize(.small); Text("…").font(D.small) }
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Get free PDF", systemImage: "arrow.down.circle")
                        .font(D.small).frame(maxWidth: .infinity).padding(.vertical, 3)
                }
            }
            .buttonStyle(.bordered)
            .disabled(downloader.active[p.id] != nil)

            if !p.url.isEmpty || !p.doi.isEmpty {
                Button {
                    if let u = SafeLink.forPaper(url: p.url, doi: p.doi) { SafeLink.open(u) }
                } label: {
                    Label("Publisher page", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 10)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private var shortcutFooter: some View {
        Button { showShortcuts = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "keyboard").font(.system(size: 10))
                Text("F keep · 1–9 exclude · J next").font(.system(size: 10))
                Spacer()
                Text("?").font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, D.s3).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("All keyboard shortcuts — press ?")
    }

    private func heading(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: D.s2) {
            HStack(spacing: 6) {
                StageBadge(stage: p.stage)
                if !p.sourceDB.isEmpty { Chip(text: p.sourceDB, color: Palette.slate) }
                if p.hasPDF { Chip(text: "PDF ready", color: Palette.emerald, icon: "doc.fill") }
                ForEach(p.sdgs, id: \.self) { Chip(text: $0, color: Palette.violet, icon: "globe") }
                Spacer()
                if !p.doi.isEmpty {
                    Link("doi.org/\(p.doi)", destination: URL(string: "https://doi.org/\(p.doi)")!)
                        .font(D.mono)
                }
            }
            Text(p.title).font(.system(size: 21, weight: .semibold)).textSelection(.enabled)
            Text("\(p.authorLine) · \(p.year.map(String.init) ?? "n.d.")\(p.venue.isEmpty ? "" : " · \(p.venue)")")
                .font(D.body).foregroundStyle(.secondary)
        }
    }

    private func criteriaCard(_ title: String, _ body: String, _ tint: Color) -> some View {
        Group {
            if body.isEmpty { EmptyView() } else {
                Card(padding: D.s3) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(tint).frame(width: 6, height: 6)
                            SectionLabel(text: title)
                        }
                        Text(body).font(D.small)
                    }
                }
            }
        }
    }

    /// Keywords, read out of the PDF or supplied by the database. Skimming a paper starts
    /// with these, so they sit above the abstract.
    @ViewBuilder
    private func keywordsBlock(_ p: Paper) -> some View {
        if !p.keywords.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(text: "Keywords")
                FlowRow(spacing: 5) {
                    ForEach(p.keywords, id: \.self) { k in
                        Button { filter = k } label: { Chip(text: k, color: Palette.slate) }
                            .buttonStyle(.plain)
                            .help("Filter this list to records mentioning “\(k)”")
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    /// The paper's own conclusion, lifted verbatim from its conclusion section. Read with the
    /// abstract, this is most of what a screening decision actually needs.
    @ViewBuilder
    private func conclusionBlock(_ p: Paper) -> some View {
        if !p.extractedConclusion.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    SectionLabel(text: p.conclusionHeading.isEmpty
                                 ? "Closing paragraphs (no conclusion heading found)"
                                 : "The paper's \(p.conclusionHeading.lowercased())")
                    Chip(text: "read from the PDF", color: Palette.emerald, icon: "doc.text.magnifyingglass")
                    Spacer()
                    Button("Use as my conclusion") {
                        var q = p
                        q.conclusion = p.extractedConclusion
                        store.updatePaper(q)
                        store.flash("Copied into your conclusion — edit it into your own words")
                    }
                    .font(D.small)
                }
                Text(p.extractedConclusion)
                    .font(.system(size: 14, design: .serif))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(D.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(D.surface)
                    .clipShape(RoundedRectangle(cornerRadius: D.radius))
                    .hairlineBorder()
            }
            .frame(maxWidth: 760, alignment: .leading)
        } else if p.hasPDF {
            HStack(spacing: 6) {
                Text("No conclusion read from this PDF yet.").font(D.small).foregroundStyle(.tertiary)
                Button("Read it now") { extractSections(p) }.font(D.small)
            }
        }
    }

    /// Pulls abstract, keywords and conclusion out of the PDF. Pure text work — no model,
    /// no network, so it also works on a paywalled paper no database will describe.
    private func extractSections(_ p: Paper) {
        guard p.hasPDF else { return }
        let s = PaperText.sections(of: URL(fileURLWithPath: p.pdfPath))
        guard s.hasTextLayer else {
            store.flash("That PDF is a scan with no text layer — nothing to read without OCR")
            return
        }
        var q = p
        if q.abstract.isEmpty { q.abstract = s.abstract }
        if q.keywords.isEmpty { q.keywords = s.keywords }
        q.extractedConclusion = s.conclusion
        q.conclusionHeading = s.conclusionHeading
        store.updatePaper(q)
        store.flash(s.isEmpty ? "Couldn't find those sections in the PDF"
                              : "Read the paper's own abstract, keywords and conclusion")
    }

    private func abstractBlock(_ p: Paper) -> some View {
        let inc = store.project?.inclusionCriteria ?? ""
        let exc = store.project?.exclusionCriteria ?? ""
        let hits = CriteriaHighlight.matchCount(p.abstract, criteria: inc)
        let misses = CriteriaHighlight.matchCount(p.abstract, criteria: exc)

        return VStack(alignment: .leading, spacing: D.s2) {
            HStack(spacing: 6) {
                SectionLabel(text: "Abstract")
                if !p.abstract.isEmpty, !inc.isEmpty || !exc.isEmpty {
                    // Your criteria words, counted before you read a line. A record matching
                    // nothing you asked for is usually a quick no.
                    if hits > 0 { Chip(text: "\(hits) include term\(hits == 1 ? "" : "s")", color: Palette.emerald) }
                    if misses > 0 { Chip(text: "\(misses) exclude term\(misses == 1 ? "" : "s")", color: Palette.rose) }
                    if hits == 0 && misses == 0 {
                        Chip(text: "no criteria words found", color: Palette.slate)
                    }
                    Spacer()
                    Toggle("Highlight criteria", isOn: $highlightCriteria)
                        .toggleStyle(.checkbox).font(D.small)
                }
            }
            if p.abstract.isEmpty {
                HStack {
                    Text("No abstract came with this record.")
                        .font(D.body).foregroundStyle(.tertiary)
                    Button("Look it up") { Task { await fetchAbstract(p) } }
                        .font(D.small)
                }
            } else if highlightCriteria, !inc.isEmpty || !exc.isEmpty {
                Text(CriteriaHighlight.attributed(p.abstract, include: inc, exclude: exc,
                                                  includeColor: Palette.emerald,
                                                  excludeColor: Palette.rose))
                    .font(.system(size: 15, design: .serif))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
            } else {
                Text(p.abstract)
                    .font(.system(size: 15, design: .serif))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    /// Your own reading of the paper, kept beside the abstract so screening and note-taking
    /// are the same motion.
    private func notesBlock(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: D.s3) {
            editor("Conclusion — what this paper actually concludes",
                   "In your own words. Carried into the report and the export.",
                   text: field(p, \.conclusion, "conclusion"), height: 78)
            editor("What I still need to read in it",
                   "Sections worth going back to, questions left open.",
                   text: field(p, \.toRead, "what is left to read"), height: 60)
            editor("Notes", "", text: field(p, \.notes, "notes"), height: 60)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    /// Writes on a pause rather than on every keystroke, so the paper is not reloaded
    /// underneath the insertion point while you are still using it. See `StableTextEditor`.
    private func field(_ p: Paper, _ path: WritableKeyPath<Paper, String>,
                       _ name: String) -> Binding<String> {
        Binding(get: { p[keyPath: path] },
                set: { value in
                    var q = p
                    q[keyPath: path] = value
                    store.updatePaper(q, undoName: "an edit to \(name)",
                                      coalesceKey: "paper-\(p.id)-\(name)")
                })
    }

    private func editor(_ label: String, _ hint: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label)
            if !hint.isEmpty { Text(hint).font(.system(size: 10)).foregroundStyle(.tertiary) }
            StableTextEditor(text: text)
                .frame(height: height)
                .background(D.surface).clipShape(RoundedRectangle(cornerRadius: D.radius))
                .hairlineBorder()
        }
    }

    private func verdictCard(_ v: Assistant.ScreenVerdict) -> some View {
        Card(padding: D.s3) {
            HStack(alignment: .top, spacing: D.s3) {
                Image(systemName: v.include ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(v.include ? Palette.emerald : Palette.rose)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(v.include ? "Claude suggests including" : "Claude suggests excluding")
                            .font(D.body.weight(.medium))
                        AIBadge()
                        Chip(text: "\(v.confidence) confidence", color: Palette.slate)
                    }
                    Text(v.reason).font(D.small).foregroundStyle(.secondary)
                    Text("A suggestion. Your decision is what gets recorded.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Accept") {
                    if v.include { decide(mode == .titleAbstract ? .sought : .included) }
                    else { decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility,
                                  reason: v.reason) }
                }
                .buttonStyle(.bordered)
            }
        }
        .background(Palette.violet.opacity(0.05))
    }

    private func commitCustom() {
        let reason = customReason.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else { return }
        decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility, reason: reason)
        customReason = ""
    }

    // MARK: Actions

    /// Moves to the next record before recording the decision, so the list doesn't jump
    /// out from under you when the current row leaves the queue.
    private func decide(_ stage: Stage, reason: String = "") {
        guard let p = current else { return }
        let next = queue.indices.contains(index + 1) ? queue[index + 1].id
                 : (index > 0 ? queue[index - 1].id : nil)

        // If the assistant had an opinion about this record, record whether the human went
        // with it. This is the whole point: not that AI was used, but that it was checked.
        if let v = verdict {
            let humanIncluded = (stage == .sought || stage == .included)
            store.resolveLatestAI(subjectKind: "paper", subjectId: p.id,
                                  v.include == humanIncluded ? .accepted : .rejected,
                                  note: humanIncluded ? "Researcher kept it" : "Researcher excluded it")
        }
        store.setStage(p.id, stage, reason: reason)
        if mode != .decided { selectedId = next }
        verdict = nil
    }

    private func step(_ delta: Int) {
        let i = index + delta
        guard queue.indices.contains(i) else { return }
        selectedId = queue[i].id
    }

    private func fetchAbstract(_ p: Paper) async {
        guard let m = await Importers.lookupOnline(doi: p.doi, title: p.title, year: p.year),
              !m.abstract.isEmpty else {
            store.flash("No abstract found for this record")
            return
        }
        var q = p
        q.abstract = m.abstract
        if q.venue.isEmpty { q.venue = m.venue }
        if q.sdgs.isEmpty { q.sdgs = m.sdgs }
        if q.references.isEmpty { q.references = m.references }
        store.updatePaper(q)
        store.flash("Abstract retrieved")
    }

    private func suggestForCurrent() async {
        guard let p = current, let proj = store.project else { return }
        await assistant.detectModel()
        verdict = await assistant.screen(paper: p, inclusion: proj.inclusionCriteria,
                                         exclusion: proj.exclusionCriteria, question: proj.question)
        if let v = verdict {
            // Logged the moment it is made, not when it is acted on — a suggestion the
            // researcher ignores is part of the record too.
            store.logAI(kind: .screen, model: assistant.lastModel,
                        subjectKind: "paper", subjectId: p.id,
                        asked: "Screen against the review criteria",
                        said: (v.include ? "include" : "exclude") + ": " + v.reason,
                        confidence: v.confidence)
        } else if !assistant.lastError.isEmpty { store.flash(assistant.lastError) }
    }

    private func autoScreenAll() async {
        guard let proj = store.project else { return }
        await assistant.detectModel()
        autoScreening = true
        defer { autoScreening = false; autoProgress = "" }
        let batch = queue
        for (i, p) in batch.enumerated() {
            autoProgress = "\(i + 1)/\(batch.count)"
            guard let v = await assistant.screen(paper: p, inclusion: proj.inclusionCriteria,
                                                 exclusion: proj.exclusionCriteria, question: proj.question)
            else { continue }
            // Recorded in the trail rather than pasted into the researcher's own notes,
            // where it would become indistinguishable from something they wrote themselves.
            store.logAI(kind: .screen, model: assistant.lastModel,
                        subjectKind: "paper", subjectId: p.id,
                        asked: "Pre-screen against the review criteria",
                        said: (v.include ? "include" : "exclude") + ": " + v.reason,
                        confidence: v.confidence)
        }
        store.flash("\(batch.count) recommendations recorded in the AI trail — none of them decided anything")
    }

    /// Shortcuts chosen so the left hand can stay on the home row through a whole screening
    /// session. Nothing here needs a modifier or a reach across the keyboard.
    ///
    ///   F  keep          D  exclude (no reason recorded)
    ///   1–9 exclude with that reason, straight from the list on the right
    ///   J / K  next and previous, ← → also work
    ///   R  open the full text     ?  this list
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard nav.section == .screening, !event.modifierFlags.contains(.command) else { return event }
            // Never steal a keystroke while a note or a reason is being typed.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }

            switch event.keyCode {
            case 124: step(1); return nil            // →
            case 123: step(-1); return nil           // ←
            case 125: step(1); return nil            // ↓
            case 126: step(-1); return nil           // ↑
            default: break
            }

            guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return event }

            if chars == "?" || (chars == "/" && event.modifierFlags.contains(.shift)) {
                showShortcuts.toggle(); return nil
            }
            if chars == "j" { step(1); return nil }
            if chars == "k" { step(-1); return nil }
            if chars == "r" {
                if let p = current, p.hasPDF { nav.read(p.id) }
                return nil
            }
            guard mode != .decided else { return event }

            // A digit picks the exclusion reason at that position in the rail, so the reason
            // is recorded without ever reaching for the mouse.
            if let digit = Int(chars), (1...9).contains(digit),
               ExcludeButton.commonReasons.indices.contains(digit - 1) {
                decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility,
                       reason: ExcludeButton.commonReasons[digit - 1])
                return nil
            }

            switch chars {
            case "f", "i": decide(mode == .titleAbstract ? .sought : .included); return nil
            case "d", "e": decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility)
                           return nil
            default: return event
            }
        }
    }
}

/// The shortcut reference, opened with `?`. Screening is repetitive by nature; the keys are
/// what stop it being repetitive with a mouse.
struct ShortcutSheet: View {
    var done: () -> Void

    private struct Row: Identifiable {
        let id = UUID()
        let keys: [String]
        let what: String
        let note: String
    }

    private let screening: [Row] = [
        .init(keys: ["F"], what: "Keep this record", note: "Index finger, home row"),
        .init(keys: ["1", "…", "9"], what: "Exclude with that reason", note: "Position in the list on the right"),
        .init(keys: ["D"], what: "Exclude without a reason", note: "PRISMA wants a reason — prefer 1–9"),
        .init(keys: ["J"], what: "Next record", note: "Or → / ↓"),
        .init(keys: ["K"], what: "Previous record", note: "Or ← / ↑"),
        .init(keys: ["R"], what: "Open the full text", note: ""),
        .init(keys: ["?"], what: "This list", note: ""),
    ]

    private let reader: [Row] = [
        .init(keys: ["1", "…", "9"], what: "Highlight the selection in that colour",
              note: "The number shown next to each tag"),
        .init(keys: ["E"], what: "Record as evidence", note: "What the source says"),
        .init(keys: ["I"], what: "Record as interpretation", note: "What you think"),
        .init(keys: ["Q"], what: "Record as a question", note: "What you don't know yet"),
        .init(keys: ["["], what: "Previous paper", note: "] for the next one"),
        .init(keys: ["N"], what: "Write a note on the last highlight", note: "No scrolling to find it"),
        .init(keys: ["F"], what: "Reading mode", note: "Every panel away; ⌃⌘F anywhere"),
        .init(keys: ["H"], what: "Hide or show your highlights", note: "Read the page clean"),
        .init(keys: ["+", "−"], what: "Zoom in and out", note: "Zoom is kept per paper"),
        .init(keys: ["0"], what: "Fit the width", note: ""),
        .init(keys: ["esc"], what: "Close the note, then the selection, then reading mode", note: ""),
        .init(keys: ["⌘", "F"], what: "Find in the document", note: ""),
    ]

    private let app: [Row] = [
        .init(keys: ["⌘", "1", "…", "9"], what: "Jump to a section", note: "In sidebar order"),
        .init(keys: ["⌘", "O"], what: "Import PDFs", note: ""),
        .init(keys: ["⌘", "⇧", "I"], what: "Import .bib / .ris", note: ""),
        .init(keys: ["⌘", "⇧", "N"], what: "New review", note: ""),
        .init(keys: ["⌘", "Z"], what: "Undo", note: "The note you are typing first, then the library"),
        .init(keys: ["⌘", "⇧", "Z"], what: "Redo", note: ""),
        .init(keys: ["⌃", "⌘", "F"], what: "Reading mode", note: "Works from any screen"),
        .init(keys: ["⌃", "⌘", "H"], what: "Hide or show your highlights", note: ""),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: D.s4) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keyboard shortcuts").font(D.title)
                Text("Screening keys sit under the left hand so you can work through a queue without moving it.")
                    .font(D.small).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: D.s5) {
                section("Screening", screening)
                VStack(alignment: .leading, spacing: D.s4) {
                    section("Reader", reader)
                    section("Anywhere", app)
                }
            }
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(D.s5).frame(width: 660)
    }

    private func section(_ title: String, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: D.s3) {
                    HStack(spacing: 2) {
                        ForEach(Array(row.keys.enumerated()), id: \.offset) { _, k in
                            Text(k)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .frame(minWidth: 20)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .frame(width: 108, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.what).font(D.body)
                        if !row.note.isEmpty {
                            Text(row.note).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 280, alignment: .leading)
    }
}
