import SwiftUI
import AppKit

/// Tags are the app's spine: a tag is a colour, a name, a coding rule and a keyboard
/// shortcut all at once. Change a colour here and every highlight in every PDF follows.
struct TagsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Tag? = nil
    @State private var showNew = false
    @State private var newKind = "category"

    var body: some View {
        VStack(spacing: 0) {
            Toolbar {
                Text("Tags").font(D.body.weight(.medium))
                Text("Four independent axes. A passage can be a Finding, about Trust, marked Important, and Qualitative — all at once.")
                    .font(D.small).foregroundStyle(.secondary)
                Spacer()
                UndoRedoButtons(history: store.history, store: store)
                Menu {
                    ForEach(TagKind.allCases) { k in
                        Button(k.label) { newKind = k.rawValue; showNew = true }
                    }
                } label: { Label("New tag", systemImage: "plus") }
                    .frame(width: 110)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: D.s5) {
                    ForEach(TagKind.allCases) { kind in
                        let items = store.tags.filter { $0.tagKind == kind }
                        if !items.isEmpty || kind == .type || kind == .theme {
                            section(kind, items)
                        }
                    }
                }
                .padding(D.s5)
            }
        }
        .background(D.canvas)
        .sheet(isPresented: $showNew) { TagEditor(tag: nil, kind: newKind) { showNew = false } }
        .sheet(item: $editing) { t in TagEditor(tag: t, kind: t.kind) { editing = nil } }
    }

    private func section(_ kind: TagKind, _ items: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: D.s3) {
            HStack(spacing: 6) {
                Image(systemName: kind.icon).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label).font(D.heading)
                    Text(kind.blurb).font(D.small).foregroundStyle(.secondary)
                }
                Spacer()
                Button { newKind = kind.rawValue; showNew = true } label: {
                    Label("Add", systemImage: "plus").font(D.small)
                }
            }
            if items.isEmpty {
                Text(kind == .theme
                     ? "No themes yet. Themes are what you're tracing across the corpus — add them as they emerge from the coding, not before."
                     : "None yet.")
                    .font(D.small).foregroundStyle(.tertiary)
                    .padding(.vertical, D.s2)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: D.s3)],
                          alignment: .leading, spacing: D.s3) {
                    ForEach(items) { t in tagCard(t) }
                }
            }
        }
    }

    private func tagCard(_ t: Tag) -> some View {
        let uses = store.evidenceCount(forTag: t.id)
        return Card(padding: D.s3) {
            VStack(alignment: .leading, spacing: D.s2) {
                HStack(spacing: D.s2) {
                    RoundedRectangle(cornerRadius: 4).fill(t.color).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.name).font(D.body.weight(.medium))
                        Text("\(uses) highlight\(uses == 1 ? "" : "s")").font(D.small).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !t.shortcut.isEmpty {
                        Text(t.shortcut)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Menu {
                        Button("Edit…") { editing = t }
                        Button("Move up") { store.moveTag(t.id, up: true) }
                        Button("Move down") { store.moveTag(t.id, up: false) }
                        Divider()
                        Button(uses > 0 ? "Delete (\(uses) highlights lose this tag)" : "Delete",
                               role: .destructive) { store.deleteTag(t.id) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 22)
                }
                if !t.detail.isEmpty {
                    Text(t.detail).font(D.small).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onTapGesture(count: 2) { editing = t }
    }
}

struct TagEditor: View {
    let tag: Tag?
    let kind: String
    var done: () -> Void

    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var detail = ""
    @State private var colorHex = Palette.blueHex
    @State private var shortcut = ""
    @State private var loaded = false

    /// SwiftUI's ColorPicker opens the shared NSColorPanel, which is its own window and
    /// does not close with the sheet. It has to be dismissed explicitly.
    private func closePanel() {
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: D.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag == nil ? "New \(TagKind(rawValue: kind)?.label.lowercased() ?? "tag")" : "Edit tag")
                    .font(D.title)
                Text(TagKind(rawValue: kind)?.blurb ?? "")
                    .font(D.small).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Name")
                TextField("e.g. Sample size", text: $name).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Colour")
                Text("This is the colour the highlight gets in the PDF.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    ForEach(Palette.highlightHexes, id: \.self) { hex in
                        Button { colorHex = hex } label: {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 5)
                                    .stroke(.primary, lineWidth: colorHex == hex ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: colorHex) },
                        set: { colorHex = $0.hexString }))
                        .labelsHidden()
                        .help("Custom colour — the picker closes when you save")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Coding rule")
                Text("What counts as this tag. Shown as a tooltip in the reader, and given to Claude when it suggests tags.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                TextField("e.g. Any passage reporting how many participants took part",
                          text: $detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3, reservesSpace: true)
            }

            if kind == TagKind.type.rawValue {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Keyboard shortcut")
                    HStack(spacing: 6) {
                        ForEach(1...9, id: \.self) { i in
                            let s = String(i)
                            let takenBy = store.tags.first { $0.shortcut == s && $0.id != tag?.id }
                            Button { shortcut = shortcut == s ? "" : s } label: {
                                Text(s)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 26, height: 26)
                                    .background(shortcut == s ? Palette.accent.opacity(0.2) : Color.secondary.opacity(0.08))
                                    .foregroundStyle(takenBy != nil ? .tertiary : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .help(takenBy.map { "Currently used by \($0.name)" } ?? "Free")
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { closePanel(); done() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    closePanel()
                    if var t = tag {
                        t.name = name; t.detail = detail; t.colorHex = colorHex; t.shortcut = shortcut
                        store.updateTag(t)
                        // Existing highlights follow the tag's colour so the corpus stays coherent.
                        for var e in store.evidence where e.tagIds.contains(t.id) && e.colorHex != colorHex {
                            e.colorHex = colorHex
                            store.updateEvidence(e)
                        }
                    } else {
                        let id = store.addTag(name: name, color: colorHex, kind: kind, detail: detail)
                        if !shortcut.isEmpty, var t = store.tag(id) { t.shortcut = shortcut; store.updateTag(t) }
                    }
                    done()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(D.s5).frame(width: 520)
        .onAppear {
            guard !loaded else { return }
            if let t = tag { name = t.name; detail = t.detail; colorHex = t.colorHex; shortcut = t.shortcut }
            else if kind == TagKind.datatype.rawValue { colorHex = "#7C8AA3" }
            else if kind == TagKind.status.rawValue { colorHex = Palette.orangeHex }
            else if kind == TagKind.theme.rawValue { colorHex = Palette.tealHex }
            loaded = true
        }
        .onDisappear { closePanel() }
    }
}
