import SwiftUI
import AppKit

/// The literature review matrix: papers down the side, your own questions across the top.
/// Cells can be typed, pulled from highlights, or drafted by Claude from those highlights —
/// and a cell always remembers which highlights it was built from.
struct MatrixView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var nav: Navigator

    @State private var showAll = false
    @State private var editing: (paper: Int, column: Int)? = nil
    @State private var newColumnName = ""
    @State private var showNewColumn = false
    @State private var fillingAll = false
    @State private var fillProgress = ""

    private let rowHeight: CGFloat = 132
    private let firstColWidth: CGFloat = 250

    private var rows: [Paper] { showAll ? store.papers.filter { !$0.stage.isExcluded } : store.included }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if store.columns.isEmpty {
                EmptyState(icon: "tablecells", title: "No columns yet",
                           message: "Columns are the questions you ask of every paper.",
                           action: ("Add a column", { showNewColumn = true }))
            } else if rows.isEmpty {
                EmptyState(icon: "tablecells",
                           title: showAll ? "No papers yet" : "No papers included yet",
                           message: showAll
                            ? "Add papers from Find papers or drop PDFs into the window."
                            : "The matrix shows the papers you've included. Screen some records first, or switch on “Show all”.",
                           action: ("Go to screening", { nav.section = .screening }))
            } else {
                grid
            }
        }
        .background(D.canvas)
        .sheet(isPresented: $showNewColumn) { newColumnSheet }
    }

    private var toolbar: some View {
        Toolbar {
            Text("Literature review matrix").font(D.body.weight(.medium))
            Text("\(rows.count) papers × \(store.columns.count) columns")
                .font(D.small).foregroundStyle(.secondary)
            Toggle("Show all non-excluded", isOn: $showAll).toggleStyle(.checkbox).font(D.small)
            Spacer()
            if Assistant.isAvailable && assistant.enabled {
                Button {
                    Task { await fillEmpty() }
                } label: {
                    if fillingAll { HStack { ProgressView().controlSize(.small); Text(fillProgress) } }
                    else { Label("Draft empty cells", systemImage: "sparkle") }
                }
                .disabled(fillingAll || rows.isEmpty)
                .help("Claude drafts each empty cell from that paper's own highlights. Drafts are flagged so you can check them.")
            }
            Button { showNewColumn = true } label: { Label("Add column", systemImage: "plus") }
            Menu {
                Button("Excel spreadsheet (.xlsx)") { Exporters.exportMatrixXLSX(store, rows: rows) }
                Button("PDF table") { Exporters.exportMatrixPDF(store, rows: rows) }
                Button("CSV") { Exporters.exportMatrixCSV(store, rows: rows) }
                Button("Markdown") { Exporters.exportMatrixMarkdown(store, rows: rows) }
                Button("Copy to clipboard (paste into Excel/Sheets)") { Exporters.copyMatrixTSV(store, rows: rows) }
                Divider()
                Button("Everything in one folder…") { Exporters.exportEverything(store) }
                Button("Full review report as PDF") { Exporters.exportReportPDF(store) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .frame(width: 100)
        }
    }

    private var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                SwiftUI.Section {
                    ForEach(rows) { p in
                        HStack(spacing: 0) {
                            paperCell(p)
                            ForEach(store.columns) { c in
                                cellView(p, c)
                            }
                        }
                        Divider()
                    }
                } header: {
                    headerRow
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Paper")
                .font(D.label).foregroundStyle(.secondary)
                .frame(width: firstColWidth, alignment: .leading)
                .padding(.horizontal, D.s3).padding(.vertical, D.s2)
            ForEach(store.columns) { c in
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(D.small.weight(.semibold)).lineLimit(1)
                        if !c.prompt.isEmpty {
                            Text(c.prompt).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Menu {
                        Button("Rename / edit prompt…") { renameColumn(c) }
                        Button("Move left") { store.moveColumn(c.id, left: true) }
                        Button("Move right") { store.moveColumn(c.id, left: false) }
                        Divider()
                        Button("Delete column", role: .destructive) { store.deleteColumn(c.id) }
                    } label: { Image(systemName: "chevron.down").font(.system(size: 8)) }
                        .menuStyle(.borderlessButton).frame(width: 18)
                }
                .frame(width: c.width, alignment: .leading)
                .padding(.horizontal, D.s3).padding(.vertical, D.s2)
                .overlay(alignment: .leading) { Rectangle().fill(D.hairline).frame(width: 0.5) }
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(D.hairline).frame(height: 0.5) }
    }

    private func paperCell(_ p: Paper) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.title).font(D.small.weight(.medium)).lineLimit(2)
            Text("\(p.authorLine) · \(p.year.map(String.init) ?? "n.d.")")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)

            HStack(spacing: 4) {
                StageBadge(stage: p.stage)
                let n = store.evidence(forPaper: p.id).count
                if n > 0 { Chip(text: "\(n)", color: Palette.amber, icon: "highlighter") }
                Spacer()
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                // Opening the paper is the most common thing to do from here, so it is a
                // real labelled button rather than a small glyph.
                Button { nav.read(p.id) } label: {
                    Label(p.hasPDF ? "Open paper" : "Details", systemImage: "book.fill")
                        .font(D.small)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if p.stage == .included {
                    Button { store.setStage(p.id, .eligibility, reason: "") } label: {
                        Image(systemName: "minus.circle").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Take this paper back out of the review")
                } else {
                    Button { store.setStage(p.id, .included, reason: "") } label: {
                        Image(systemName: "plus.circle").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(Palette.emerald)
                    .help("Include this paper in the review")
                }
            }
        }
        .frame(width: firstColWidth, height: rowHeight, alignment: .topLeading)
        .padding(.horizontal, D.s3).padding(.vertical, D.s2)
        .background(D.surface)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { nav.read(p.id) }
        .contextMenu {
            Button("Open in reader") { nav.read(p.id) }
            if p.stage == .included {
                Button("Remove from review") { store.setStage(p.id, .eligibility, reason: "") }
            } else {
                Button("Include in review") { store.setStage(p.id, .included, reason: "") }
            }
            Button("Copy reference") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p.reference, forType: .string)
            }
        }
    }

    private func cellView(_ p: Paper, _ c: MatrixColumn) -> some View {
        let cell = store.cell(p.id, c.id)
        let isEditing = editing?.paper == p.id && editing?.column == c.id
        return Button {
            editing = (p.id, c.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if cell.value.isEmpty {
                    Text("—").foregroundStyle(.quaternary).font(D.small)
                } else {
                    Text(cell.value).font(D.small).lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                if cell.aiGenerated || !cell.evidenceIds.isEmpty {
                    HStack(spacing: 4) {
                        if cell.aiGenerated { AIBadge() }
                        if !cell.evidenceIds.isEmpty {
                            Chip(text: "\(cell.evidenceIds.count) source\(cell.evidenceIds.count == 1 ? "" : "s")",
                                 color: Palette.amber, icon: "highlighter")
                        }
                    }
                }
            }
            .frame(width: c.width, height: rowHeight, alignment: .topLeading)
            .padding(.horizontal, D.s3).padding(.vertical, D.s2)
            .background(isEditing ? Palette.accent.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(D.hairline).frame(width: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { isEditing }, set: { if !$0 { editing = nil } })) {
            CellEditor(paper: p, column: c)
        }
    }

    private func renameColumn(_ c: MatrixColumn) {
        let alert = NSAlert()
        alert.messageText = "Edit column"
        alert.informativeText = "The prompt describes what this column asks of each paper. Claude uses it when drafting cells."
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 340, height: 58))
        stack.orientation = .vertical
        stack.spacing = 6
        let nameField = NSTextField(string: c.name)
        let promptField = NSTextField(string: c.prompt)
        promptField.placeholderString = "What this column asks for"
        nameField.frame.size.width = 340; promptField.frame.size.width = 340
        stack.addArrangedSubview(nameField); stack.addArrangedSubview(promptField)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            var q = c; q.name = nameField.stringValue; q.prompt = promptField.stringValue
            store.updateColumn(q)
        }
    }

    private var newColumnSheet: some View {
        NewColumnSheet { name, prompt in
            store.addColumn(name: name, prompt: prompt)
            showNewColumn = false
        } cancel: { showNewColumn = false }
    }

    private func fillEmpty() async {
        fillingAll = true
        defer { fillingAll = false; fillProgress = "" }
        var done = 0
        let targets = rows.flatMap { p in store.columns.map { (p, $0) } }
            .filter { store.cell($0.0.id, $0.1.id).value.isEmpty }
        for (p, c) in targets {
            done += 1
            fillProgress = "\(done)/\(targets.count)"
            let ev = store.evidence(forPaper: p.id)
            guard let text = await assistant.draftCell(column: c, paper: p, evidence: ev, tags: store.tags),
                  !text.isEmpty, text != "NOT ENOUGH EVIDENCE" else { continue }
            store.setCell(p.id, c.id, value: text, evidenceIds: ev.map(\.id), ai: true)
        }
        store.flash("Drafted \(done) cells — every one is flagged AI, check before you cite")
    }
}

struct NewColumnSheet: View {
    var create: (String, String) -> Void
    var cancel: () -> Void
    @State private var name = ""
    @State private var prompt = ""

    private static let presets = [
        ("Sample / participants", "Who was studied — how many, recruited how?"),
        ("Instrument / measure", "What tool or scale was used to collect data?"),
        ("Effect size / result", "The headline number or qualitative result."),
        ("Context / setting", "Country, discipline, lab vs field."),
        ("Data type", "Qualitative, quantitative or mixed?"),
        ("Gap identified", "What the authors say still needs studying."),
        ("Quality / risk of bias", "How trustworthy is this study?"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Text("New matrix column").font(D.title)
            Text("A column is one question you ask of every paper.").font(D.small).foregroundStyle(.secondary)
            TextField("Column name", text: $name).textFieldStyle(.roundedBorder)
            TextField("What it asks for — also the instruction Claude uses when drafting",
                      text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2, reservesSpace: true)
            SectionLabel(text: "Common columns")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], alignment: .leading, spacing: 6) {
                ForEach(Self.presets, id: \.0) { p in
                    Button { name = p.0; prompt = p.1 } label: {
                        Text(p.0).font(D.small)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Add column") { create(name, prompt) }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(D.s5).frame(width: 520)
    }
}

/// Editing a cell shows the highlights available from that paper, so filling the matrix
/// is a matter of picking evidence you already collected rather than re-reading the PDF.
struct CellEditor: View {
    let paper: Paper
    let column: MatrixColumn
    @EnvironmentObject var store: Store
    @EnvironmentObject var assistant: Assistant
    @State private var text = ""
    @State private var linked: Set<Int> = []
    @State private var loaded = false
    @State private var isAI = false

    var body: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(column.name).font(D.heading)
                Text(paper.title).font(D.small).foregroundStyle(.secondary).lineLimit(1)
                if !column.prompt.isEmpty {
                    Text(column.prompt).font(D.small).foregroundStyle(.tertiary)
                }
            }

            TextEditor(text: $text)
                .font(D.body).frame(height: 110)
                .padding(4).background(D.surface)
                .clipShape(RoundedRectangle(cornerRadius: D.radius)).hairlineBorder()

            let ev = store.evidence(forPaper: paper.id)
            if ev.isEmpty {
                Text("No highlights from this paper yet. Highlight passages in the Reader and they'll appear here to cite.")
                    .font(D.small).foregroundStyle(.tertiary)
            } else {
                SectionLabel(text: "Cite highlights from this paper")
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ev) { e in
                            Button {
                                if linked.contains(e.id) { linked.remove(e.id) } else {
                                    linked.insert(e.id)
                                    if text.isEmpty { text = e.quote }
                                    else { text += (text.hasSuffix(" ") ? "" : " ") + e.quote }
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: linked.contains(e.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(linked.contains(e.id) ? Palette.accent : Color.secondary.opacity(0.45))
                                        .font(.system(size: 11))
                                    Rectangle().fill(Color(hex: e.colorHex)).frame(width: 3)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.quote).font(D.small).lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("p.\(e.page + 1)").font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            HStack {
                if Assistant.isAvailable && assistant.enabled {
                    Button {
                        Task {
                            guard let t = await assistant.draftCell(column: column, paper: paper,
                                                                    evidence: store.evidence(forPaper: paper.id),
                                                                    tags: store.tags) else { return }
                            text = t; isAI = true
                            linked = Set(store.evidence(forPaper: paper.id).map(\.id))
                        }
                    } label: {
                        if assistant.busy { ProgressView().controlSize(.small) }
                        else { Label("Draft from highlights", systemImage: "sparkle") }
                    }
                    .disabled(assistant.busy)
                }
                Spacer()
                Button("Save") {
                    store.setCell(paper.id, column.id, value: text,
                                  evidenceIds: Array(linked), ai: isAI && !text.isEmpty)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(D.s4)
        .frame(width: 480)
        .onAppear {
            guard !loaded else { return }
            let c = store.cell(paper.id, column.id)
            text = c.value; linked = Set(c.evidenceIds); isAI = c.aiGenerated; loaded = true
        }
    }
}
