import SwiftUI
import AppKit

/// Design methods as grids that cite evidence.
///
/// A SWOT on a whiteboard is four boxes of assertion. The same SWOT here has a column asking
/// what each claim rests on, and that column links to the actual highlight, in the actual
/// source, with the date it was collected. That is the whole difference, and it is why these
/// live in the same project as the literature — a quote from an interview and a finding from
/// a paper are the same kind of object.
struct FramesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @State private var selected: Int? = nil
    @State private var showPicker = false
    @State private var editing: (row: Int, col: Int)? = nil
    @State private var renamingAxis: FrameAxis? = nil
    @AppStorage("sieve.frameListWidth") private var listWidth: Double = 230

    private var frame: Frame? {
        if let id = selected { return store.frames.first { $0.id == id } }
        return store.frames.first
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if store.frames.isEmpty {
                EmptyState(icon: "square.grid.3x3",
                           title: "No frameworks yet",
                           message: "A SWOT, a journey map, an empathy map — set up as a grid whose cells cite the evidence behind them, in the same project as your sources. That citation is the difference between this and a whiteboard.",
                           action: ("Choose a method", { showPicker = true }))
            } else {
                HStack(spacing: 0) {
                    frameList.frame(width: listWidth)
                    PaneDivider(width: $listWidth, range: 180...340)
                    if let f = frame { grid(f).frame(maxWidth: .infinity) }
                }
            }
        }
        .background(D.canvas)
        .sheet(isPresented: $showPicker) {
            FramePicker { template, name in
                let id = store.addFrame(template, name: name)
                selected = id
                showPicker = false
            } cancel: { showPicker = false }
        }
        .sheet(item: $renamingAxis) { axis in
            AxisEditor(axis: axis) { renamingAxis = nil }
        }
    }

    private var toolbar: some View {
        Toolbar {
            Text("Frameworks").font(D.body.weight(.medium))
            if let f = frame {
                let g = store.frameGrounding(f.id)
                Text("\(g.filled) of \(g.total) cells filled")
                    .font(D.small).foregroundStyle(.secondary)
                if g.filled > 0 {
                    // The number a whiteboard cannot give you.
                    Chip(text: "\(g.cited) cite evidence",
                         color: g.cited == g.filled ? Palette.emerald
                              : (g.cited == 0 ? Palette.rose : Palette.amber),
                         icon: "link")
                }
            }
            Spacer()
            Button { showPicker = true } label: { Label("New framework", systemImage: "plus") }
            if let f = frame {
                Menu {
                    Button("Export as CSV") { Exporters.exportFrameCSV(store, f) }
                    Button("Export as Markdown") { Exporters.exportFrameMarkdown(store, f) }
                    Divider()
                    Button("Delete this framework", role: .destructive) {
                        store.deleteFrame(f.id); selected = store.frames.first?.id
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).frame(width: 28)
            }
        }
    }

    private var frameList: some View {
        List(selection: Binding(get: { selected ?? store.frames.first?.id },
                                set: { selected = $0 })) {
            ForEach(store.frames) { f in
                let g = store.frameGrounding(f.id)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: f.icon).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(f.name).font(D.small.weight(.medium)).lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("\(store.rows(of: f.id).count)×\(store.cols(of: f.id).count)")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                        if g.filled > 0 {
                            Chip(text: "\(g.cited)/\(g.filled) cited",
                                 color: g.cited == g.filled ? Palette.emerald : Palette.amber)
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(f.id)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: The grid

    private func grid(_ f: Frame) -> some View {
        let rows = store.rows(of: f.id), cols = store.cols(of: f.id)
        return VStack(alignment: .leading, spacing: 0) {
            if !f.detail.isEmpty {
                Text(f.detail).font(D.small).foregroundStyle(.secondary)
                    .padding(.horizontal, D.s4).padding(.vertical, 6)
            }
            if rows.isEmpty {
                openRowsPrompt(f)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow(f, cols)
                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                rowHeader(f, row)
                                ForEach(cols) { col in cell(f, row, col) }
                            }
                            Divider()
                        }
                        addRowButton(f)
                    }
                }
            }
        }
    }

    private func openRowsPrompt(_ f: Frame) -> some View {
        let noun = f.template?.rowNoun ?? "row"
        return EmptyState(icon: "plus.rectangle.on.rectangle",
                          title: "Add your first \(noun)",
                          message: "The columns are set up. Rows are yours — one per \(noun).",
                          action: ("Add a \(noun)", { promptForRow(f) }))
    }

    private func headerRow(_ f: Frame, _ cols: [FrameAxis]) -> some View {
        HStack(spacing: 0) {
            Text(f.template?.rowNoun.capitalized ?? "Row")
                .font(D.label).foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)
                .padding(.horizontal, D.s3).padding(.vertical, D.s2)
            ForEach(cols) { col in
                HStack(spacing: 3) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(col.name).font(D.small.weight(.semibold)).lineLimit(1)
                        if !col.detail.isEmpty {
                            Text(col.detail).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("Rename…") { renamingAxis = col }
                        Button("Move left") { store.moveAxis(col.id, f.id, isRow: false, up: true) }
                        Button("Move right") { store.moveAxis(col.id, f.id, isRow: false, up: false) }
                        Divider()
                        Button("Delete column", role: .destructive) { store.deleteAxis(col.id) }
                    } label: { Image(systemName: "chevron.down").font(.system(size: 8)) }
                        .menuStyle(.borderlessButton).frame(width: 16)
                }
                .frame(width: 230, alignment: .leading)
                .padding(.horizontal, D.s3).padding(.vertical, D.s2)
                .overlay(alignment: .leading) { Rectangle().fill(D.hairline).frame(width: 0.5) }
            }
            Button { store.addAxis(f.id, isRow: false, name: "New column") } label: {
                Image(systemName: "plus").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, D.s2)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(D.hairline).frame(height: 0.5) }
    }

    private func rowHeader(_ f: Frame, _ row: FrameAxis) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.name).font(D.small.weight(.medium)).lineLimit(2)
            if !row.detail.isEmpty {
                Text(row.detail).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(3)
            }
            if let sid = row.sourceId, let p = store.paper(sid) {
                Button { nav.read(p.id) } label: {
                    Chip(text: p.citeKey, color: Palette.accent, icon: p.sourceType.icon)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Rename…") { renamingAxis = row }
                Button("Move up") { store.moveAxis(row.id, f.id, isRow: true, up: true) }
                Button("Move down") { store.moveAxis(row.id, f.id, isRow: true, up: false) }
                Divider()
                Button("Delete row", role: .destructive) { store.deleteAxis(row.id) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 9)) }
                .menuStyle(.borderlessButton).frame(width: 18)
        }
        .frame(width: 190, height: 110, alignment: .topLeading)
        .padding(.horizontal, D.s3).padding(.vertical, D.s2)
        .background(D.surface)
    }

    private func cell(_ f: Frame, _ row: FrameAxis, _ col: FrameAxis) -> some View {
        let c = store.frameCell(f.id, row.id, col.id)
        let isEditing = editing?.row == row.id && editing?.col == col.id
        return Button { editing = (row.id, col.id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                if c.value.isEmpty {
                    Text("—").font(D.small).foregroundStyle(.quaternary)
                } else {
                    Text(c.value).font(D.small).lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if c.aiGenerated { AIBadge() }
                    if !c.evidenceIds.isEmpty {
                        Chip(text: "\(c.evidenceIds.count)", color: Palette.amber, icon: "link")
                    } else if !c.value.isEmpty {
                        // Says out loud when a claim is standing on nothing.
                        Chip(text: "no evidence", color: Palette.rose)
                    }
                }
            }
            .frame(width: 230, height: 110, alignment: .topLeading)
            .padding(.horizontal, D.s3).padding(.vertical, D.s2)
            .background(isEditing ? Palette.accent.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(D.hairline).frame(width: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { isEditing }, set: { if !$0 { editing = nil } })) {
            FrameCellEditor(frame: f, row: row, col: col)
        }
    }

    private func addRowButton(_ f: Frame) -> some View {
        HStack {
            Button { promptForRow(f) } label: {
                Label("Add \(f.template?.rowNoun ?? "row")", systemImage: "plus").font(D.small)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
            if !store.ownSources.isEmpty || !store.included.isEmpty {
                Menu {
                    SwiftUI.Section("From your own material") {
                        ForEach(store.ownSources) { p in
                            Button(p.title) {
                                store.addAxis(f.id, isRow: true, name: p.title, sourceId: p.id)
                            }
                        }
                    }
                    SwiftUI.Section("From included papers") {
                        ForEach(store.included.prefix(20)) { p in
                            Button(p.citeKey + " — " + p.title.prefix(40)) {
                                store.addAxis(f.id, isRow: true, name: p.title, sourceId: p.id)
                            }
                        }
                    }
                } label: { Label("Add a row from a source", systemImage: "doc.badge.plus").font(D.small) }
                .menuStyle(.borderlessButton).frame(width: 190)
            }
        }
        .padding(D.s3)
    }

    private func promptForRow(_ f: Frame) {
        let noun = f.template?.rowNoun ?? "row"
        let alert = NSAlert()
        alert.messageText = "New \(noun)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { store.addAxis(f.id, isRow: true, name: name) }
        }
    }
}

/// Choosing a method. Each one says what it is for, because picking the wrong framework is
/// the most common way design research goes wrong.
struct FramePicker: View {
    var create: (FrameTemplate, String?) -> Void
    var cancel: () -> Void
    @State private var chosen: FrameTemplate? = nil
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: D.s4) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a framework").font(D.title)
                Text("A grid whose cells cite your evidence. It lives in this project alongside your sources, so a quote from an interview and a finding from a paper can sit in the same cell.")
                    .font(D.small).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: D.s3)],
                          alignment: .leading, spacing: D.s3) {
                    ForEach(FrameTemplate.allCases) { t in
                        Button { chosen = t; name = t.label } label: {
                            Card(padding: D.s3) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Image(systemName: t.icon).foregroundStyle(Palette.accent)
                                        Text(t.label).font(D.body.weight(.medium))
                                    }
                                    Text(t.blurb).font(D.small).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    let s = t.starting
                                    Text(s.rows.isEmpty
                                         ? "\(s.cols.count) columns · you add the \(t.rowNoun)s"
                                         : "\(s.rows.count) rows × \(s.cols.count) columns, ready to fill")
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                            }
                            .background(chosen == t ? Palette.accent.opacity(0.08) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: D.radiusL)
                                .stroke(chosen == t ? Palette.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 380)
            if chosen != nil {
                TextField("Name it", text: $name).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Add") { if let t = chosen { create(t, name.isEmpty ? nil : name) } }
                    .buttonStyle(.borderedProminent).disabled(chosen == nil)
            }
        }
        .padding(D.s5).frame(width: 780)
    }
}

struct AxisEditor: View {
    let axis: FrameAxis
    var done: () -> Void
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var detail = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Text(axis.isRow ? "Row" : "Column").font(D.title)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: "What belongs here")
                TextField("Shown under the heading as a reminder", text: $detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3, reservesSpace: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save") {
                    var a = axis; a.name = name; a.detail = detail
                    store.updateAxis(a); done()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(D.s5).frame(width: 460)
        .onAppear { if !loaded { name = axis.name; detail = axis.detail; loaded = true } }
    }
}

/// Filling a cell. The evidence list is the point: a claim in a SWOT or a journey map should
/// be traceable to the interview or the paper it came from, exactly as a matrix cell is.
struct FrameCellEditor: View {
    let frame: Frame
    let row: FrameAxis
    let col: FrameAxis
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @State private var text = ""
    @State private var linked: Set<Int> = []
    @State private var search = ""
    @State private var loaded = false
    @State private var stanceFilter: Stance? = nil

    private var candidates: [Evidence] {
        store.evidence.filter { e in
            (stanceFilter == nil || e.stance == stanceFilter!)
            && (search.isEmpty
                || e.quote.localizedCaseInsensitiveContains(search)
                || (store.paper(e.paperId)?.title.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.name) · \(col.name)").font(D.heading)
                if !col.detail.isEmpty {
                    Text(col.detail).font(D.small).foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $text)
                .font(D.body).frame(height: 90).padding(4)
                .background(D.surface).clipShape(RoundedRectangle(cornerRadius: D.radius))
                .hairlineBorder()

            HStack(spacing: 5) {
                SectionLabel(text: "What this rests on")
                if linked.isEmpty && !text.isEmpty {
                    Chip(text: "nothing cited", color: Palette.rose)
                } else if !linked.isEmpty {
                    Chip(text: "\(linked.count) cited", color: Palette.emerald, icon: "link")
                }
                Spacer()
                ForEach(Stance.allCases) { st in
                    Button { stanceFilter = stanceFilter == st ? nil : st } label: {
                        Chip(text: st.label, color: st.color, filled: stanceFilter == st)
                    }
                    .buttonStyle(.plain)
                }
            }

            SearchField(placeholder: "Find a highlight from any source", text: $search)

            if store.evidence.isEmpty {
                Text("No highlights yet. Read a source and mark passages in the Reader — interviews, papers and web pages all work the same way — and they become citable here.")
                    .font(D.small).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(candidates.prefix(80)) { e in
                            Button {
                                if linked.contains(e.id) { linked.remove(e.id) } else {
                                    linked.insert(e.id)
                                    if text.isEmpty { text = e.quote }
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: linked.contains(e.id) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 11))
                                        .foregroundStyle(linked.contains(e.id) ? Palette.accent
                                                         : Color.secondary.opacity(0.4))
                                    Rectangle().fill(Color(hex: e.colorHex)).frame(width: 3)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.quote).font(D.small).lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        HStack(spacing: 4) {
                                            Chip(text: e.stance.label, color: e.stance.color)
                                            if let p = store.paper(e.paperId) {
                                                Chip(text: p.citeKey, color: Palette.slate,
                                                     icon: p.sourceType.icon)
                                            }
                                        }
                                    }
                                }
                                .padding(5)
                                .background(linked.contains(e.id) ? Palette.accent.opacity(0.07) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 200)
            }

            HStack {
                Spacer()
                Button("Save") {
                    store.setFrameCell(frame.id, row.id, col.id, value: text,
                                       evidenceIds: Array(linked))
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(D.s4).frame(width: 520)
        .onAppear {
            guard !loaded else { return }
            let c = store.frameCell(frame.id, row.id, col.id)
            text = c.value; linked = Set(c.evidenceIds); loaded = true
        }
    }
}
