import SwiftUI
import AppKit

/// Title/abstract screening, full-text assessment, and a record of what you already decided.
/// Every decision is reversible: nothing here is a one-way door.
struct ScreeningView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var nav: Navigator
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
            VStack(spacing: 0) {
                ZStack {
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
                        .padding(.horizontal, 28)          // room for the side arrows
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    sideArrows
                }
                Divider()
                decisionBar(p)
            }
        } else {
            EmptyState(icon: "doc.text", title: "Nothing selected", message: "Pick a record on the left.")
        }
    }

    /// Big click targets pinned to the left and right edges — the same movement as flicking
    /// through cards, without hunting for a button.
    private var sideArrows: some View {
        HStack {
            arrowButton("chevron.left", enabled: index > 0) { step(-1) }
            Spacer()
            arrowButton("chevron.right", enabled: index < queue.count - 1) { step(1) }
        }
        .padding(.horizontal, 4)
    }

    private func arrowButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 58)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(D.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 0.9 : 0.25)
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
        VStack(alignment: .leading, spacing: D.s2) {
            SectionLabel(text: "Abstract")
            if p.abstract.isEmpty {
                HStack {
                    Text("No abstract came with this record.")
                        .font(D.body).foregroundStyle(.tertiary)
                    Button("Look it up") { Task { await fetchAbstract(p) } }
                        .font(D.small)
                }
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
                   text: Binding(get: { p.conclusion },
                                 set: { var q = p; q.conclusion = $0; store.updatePaper(q) }),
                   height: 78)
            editor("What I still need to read in it",
                   "Sections worth going back to, questions left open.",
                   text: Binding(get: { p.toRead },
                                 set: { var q = p; q.toRead = $0; store.updatePaper(q) }),
                   height: 60)
            editor("Notes", "",
                   text: Binding(get: { p.notes },
                                 set: { var q = p; q.notes = $0; store.updatePaper(q) }),
                   height: 60)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func editor(_ label: String, _ hint: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label)
            if !hint.isEmpty { Text(hint).font(.system(size: 10)).foregroundStyle(.tertiary) }
            TextEditor(text: text)
                .font(D.body).frame(height: height).padding(4)
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

    // MARK: Bottom bar

    private func decisionBar(_ p: Paper) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: D.s3) {
                Button { step(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                    .disabled(index == 0)
                Button { step(1) } label: { Label("Next", systemImage: "chevron.right") }
                    .disabled(index >= queue.count - 1)

                Spacer()

                if p.hasPDF {
                    Button { extractSections(p) } label: {
                        Label("Re-read the PDF", systemImage: "doc.text.magnifyingglass")
                    }
                    .help("Pull the abstract, keywords and conclusion out of the PDF again")
                }
                if p.hasPDF || !p.pdfURL.isEmpty {
                    Button { nav.read(p.id) } label: { Label("Read full text", systemImage: "book") }
                }

                if mode == .decided {
                    // Any decision can be taken back — that is the whole point of this tab.
                    Button {
                        store.setStage(p.id, .screening, reason: "")
                        store.flash("Sent back to screening — decide again when you're ready")
                    } label: { Label("Undo decision", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                    if p.stage != .included {
                        Button { store.setStage(p.id, .included, reason: "") } label: {
                            Label("Include instead", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent).tint(Palette.emerald)
                    } else {
                        Button { showExclude = true } label: { Label("Exclude instead", systemImage: "xmark") }
                            .buttonStyle(.bordered).tint(Palette.rose)
                            .popover(isPresented: $showExclude) { excludePopover }
                    }
                } else {
                    Button { showExclude = true } label: {
                        Label("Exclude…", systemImage: "xmark").frame(width: 92)
                    }
                    .buttonStyle(.bordered).tint(Palette.rose)
                    .popover(isPresented: $showExclude) { excludePopover }

                    Button {
                        decide(mode == .titleAbstract ? .sought : .included)
                    } label: {
                        Label(mode == .titleAbstract ? "Keep — get full text" : "Include in review",
                              systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent).tint(Palette.emerald)
                }
            }
            .padding(.horizontal, D.s4).padding(.vertical, D.s3)

            Text(mode == .decided
                 ? "Decisions are never final — reopen any record here"
                 : "I include · E exclude · → next · ← previous")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .padding(.bottom, 6)
        }
        .background(.bar)
    }

    private var excludePopover: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            Text("Reason for exclusion").font(D.heading)
            Text("Recorded against the paper and counted in your PRISMA diagram.")
                .font(D.small).foregroundStyle(.secondary)
            ForEach(ExcludeButton.commonReasons, id: \.self) { r in
                Button(r) {
                    decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility, reason: r)
                    showExclude = false
                }
                .buttonStyle(.plain).font(D.body)
            }
            Divider()
            HStack {
                TextField("Other…", text: $customReason).textFieldStyle(.roundedBorder)
                    .onSubmit { commitCustom() }
                Button("Exclude") { commitCustom() }.disabled(customReason.isEmpty)
            }
        }
        .padding(D.s4).frame(width: 330)
    }

    private func commitCustom() {
        guard !customReason.isEmpty else { return }
        decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility, reason: customReason)
        customReason = ""; showExclude = false
    }

    // MARK: Actions

    /// Moves to the next record before recording the decision, so the list doesn't jump
    /// out from under you when the current row leaves the queue.
    private func decide(_ stage: Stage, reason: String = "") {
        guard let p = current else { return }
        let next = queue.indices.contains(index + 1) ? queue[index + 1].id
                 : (index > 0 ? queue[index - 1].id : nil)
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
        verdict = await assistant.screen(paper: p, inclusion: proj.inclusionCriteria,
                                         exclusion: proj.exclusionCriteria, question: proj.question)
        if verdict == nil, !assistant.lastError.isEmpty { store.flash(assistant.lastError) }
    }

    private func autoScreenAll() async {
        guard let proj = store.project else { return }
        autoScreening = true
        defer { autoScreening = false; autoProgress = "" }
        let batch = queue
        for (i, p) in batch.enumerated() {
            autoProgress = "\(i + 1)/\(batch.count)"
            guard let v = await assistant.screen(paper: p, inclusion: proj.inclusionCriteria,
                                                 exclusion: proj.exclusionCriteria, question: proj.question)
            else { continue }
            var q = p
            let line = "[Claude, \(Date().formatted(date: .abbreviated, time: .omitted))] "
                + (v.include ? "suggests INCLUDE" : "suggests EXCLUDE")
                + " (\(v.confidence)): \(v.reason)"
            q.notes = q.notes.isEmpty ? line : q.notes + "\n" + line
            store.updatePaper(q)
        }
        store.flash("Claude left a recommendation on \(batch.count) records — decisions are still yours")
    }

    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard nav.section == .screening, !event.modifierFlags.contains(.command) else { return event }
            // Never steal a keystroke while a note is being typed.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            switch event.keyCode {
            case 124: step(1); return nil
            case 123: step(-1); return nil
            default: break
            }
            guard mode != .decided else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "i": decide(mode == .titleAbstract ? .sought : .included); return nil
            case "e": decide(mode == .titleAbstract ? .excludedScreening : .excludedEligibility); return nil
            default: return event
            }
        }
    }
}
