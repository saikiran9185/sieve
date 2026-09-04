import SwiftUI
import AppKit

/// A method is an ordered list of steps you choose — not a workflow the app imposes. Pick a
/// preset, edit it, or build one from nothing. The steps decide what Sieve puts in front of
/// you; the evidence underneath is the same whichever method you run over it.
struct MethodView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @State private var editing: Method? = nil
    @State private var showBuilder = false

    private var active: Method? { store.activeMethod }
    private var templates: [Method] { store.methods.filter(\.isTemplate) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: D.s5) {
                header
                if let m = active { activeMethodCard(m) } else { noMethodCard }
                presetsSection
                Card {
                    VStack(alignment: .leading, spacing: D.s2) {
                        SectionLabel(text: "Why this exists")
                        Text("Most review software makes you adopt its methodology before you can use it. Sieve keeps the evidence — sources, highlights, codes, relations — separate from the method you run over it, so PRISMA screening and thematic coding can happen in the same project, on the same passages, without either owning the data.")
                            .font(D.small).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(D.s5).frame(maxWidth: 900, alignment: .leading)
        }
        .background(D.canvas)
        .sheet(isPresented: $showBuilder) {
            MethodBuilder(method: editing ?? Method(id: 0, projectId: store.currentProjectId,
                                                    name: "", blocks: [])) {
                showBuilder = false; editing = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            Text("Method").font(.system(size: 26, weight: .semibold))
            Text("How you work on this review. Steps are a guide, never a gate — every part of Sieve stays reachable whatever method you pick.")
                .font(D.body).foregroundStyle(.secondary)
        }
    }

    private var noMethodCard: some View {
        Card {
            VStack(alignment: .leading, spacing: D.s3) {
                Text("No method chosen").font(D.heading)
                Text("You don't need one — the whole app works without it. A method just gives you an ordered path through the work and shows how far along you are.")
                    .font(D.small).foregroundStyle(.secondary)
                HStack {
                    Button("Build one from scratch") { editing = nil; showBuilder = true }
                        .buttonStyle(.borderedProminent)
                    Text("or pick a preset below").font(D.small).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func activeMethodCard(_ m: Method) -> some View {
        VStack(alignment: .leading, spacing: D.s3) {
            HStack {
                SectionLabel(text: "This review's method")
                Spacer()
                Button("Edit steps") { editing = m; showBuilder = true }.font(D.small)
                Button("Save as a reusable recipe") { saveAsRecipe(m) }.font(D.small)
                Button("Remove", role: .destructive) { store.deleteMethod(m.id) }.font(D.small)
            }
            Card {
                VStack(alignment: .leading, spacing: D.s4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(D.heading)
                        if !m.detail.isEmpty {
                            Text(m.detail).font(D.small).foregroundStyle(.secondary)
                        }
                    }
                    steps(m)
                }
            }
        }
    }

    /// The steps as a path, with the one you're on marked. Clicking a step goes to the screen
    /// where that work happens — it never locks the others.
    private func steps(_ m: Method) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(m.blocks.enumerated()), id: \.offset) { i, block in
                HStack(alignment: .top, spacing: D.s3) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(i < m.currentStep ? Palette.emerald
                                      : (i == m.currentStep ? Palette.accent : Color.secondary.opacity(0.18)))
                                .frame(width: 26, height: 26)
                            if i < m.currentStep {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(i + 1)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(i == m.currentStep ? .white : .secondary)
                            }
                        }
                        if i < m.blocks.count - 1 {
                            Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1.5, height: 26)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: block.icon).font(.system(size: 11))
                                .foregroundStyle(i == m.currentStep ? Palette.accent : .secondary)
                            Text(block.label)
                                .font(D.body.weight(i == m.currentStep ? .semibold : .regular))
                            Spacer()
                            if i == m.currentStep {
                                Button("Go") { go(block) }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                                Button("Mark done") {
                                    var q = m; q.currentStep = min(i + 1, m.blocks.count); store.saveMethod(q)
                                }
                                .controlSize(.small)
                            } else {
                                Button("Open") { go(block) }
                                    .buttonStyle(.plain).font(D.small).foregroundStyle(Palette.accent)
                                if i < m.currentStep {
                                    Button("Redo") { var q = m; q.currentStep = i; store.saveMethod(q) }
                                        .buttonStyle(.plain).font(D.small).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Text(block.blurb).font(D.small).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, i < m.blocks.count - 1 ? D.s3 : 0)
                }
            }
        }
    }

    private func go(_ block: MethodBlock) {
        if let s = Section(rawValue: block.section) { nav.section = s }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            SectionLabel(text: active == nil ? "Start from a method" : "Other methods")
            Text("Presets are templates, not rails. Adopting one copies its steps into this review, where you can change them.")
                .font(D.small).foregroundStyle(.tertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: D.s3)],
                      alignment: .leading, spacing: D.s3) {
                ForEach(templates) { t in
                    Card(padding: D.s3) {
                        VStack(alignment: .leading, spacing: D.s2) {
                            Text(t.name).font(D.body.weight(.medium))
                            Text(t.detail).font(D.small).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            FlowRow(spacing: 4) {
                                ForEach(Array(t.blocks.enumerated()), id: \.offset) { _, b in
                                    Chip(text: b.label, color: Palette.slate, icon: b.icon)
                                }
                            }
                            HStack {
                                Button("Use this") { store.adopt(t); store.flash("Method set to \(t.name)") }
                                    .buttonStyle(.bordered).controlSize(.small)
                                Spacer()
                                if t.projectId == nil && !isBuiltIn(t) {
                                    Button("Delete", role: .destructive) { store.deleteMethod(t.id) }
                                        .buttonStyle(.plain).font(D.small)
                                }
                            }
                        }
                    }
                }
                Card(padding: D.s3) {
                    VStack(alignment: .leading, spacing: D.s2) {
                        Text("Build your own").font(D.body.weight(.medium))
                        Text("Pick the steps your discipline actually uses, in the order you actually work.")
                            .font(D.small).foregroundStyle(.secondary)
                        Button("Open the builder") { editing = nil; showBuilder = true }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
        }
    }

    private func isBuiltIn(_ m: Method) -> Bool {
        ["Systematic review (PRISMA)", "Scoping review", "Literature review", "Thematic analysis",
         "Grounded theory", "Content analysis", "Comparative analysis", "Just reading"].contains(m.name)
    }

    /// Saving a method as a recipe makes it available to every future review.
    private func saveAsRecipe(_ m: Method) {
        let alert = NSAlert()
        alert.messageText = "Save as a reusable recipe"
        alert.informativeText = "It will appear as a preset in every review you start."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = m.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var copy = m
        copy.id = 0
        copy.projectId = nil
        copy.isTemplate = true
        copy.name = field.stringValue.isEmpty ? m.name : field.stringValue
        copy.currentStep = 0
        store.saveMethod(copy)
        store.flash("Saved “\(copy.name)” — available in every review")
    }
}

// MARK: - Builder

struct MethodBuilder: View {
    @State var method: Method
    var done: () -> Void
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: D.s4) {
            Text(method.id > 0 ? "Edit method" : "Build a method").font(D.title)

            TextField("Name — e.g. My design research process", text: $method.name)
                .textFieldStyle(.roundedBorder)
            TextField("What it is for", text: $method.detail, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2, reservesSpace: true)

            HStack(alignment: .top, spacing: D.s4) {
                VStack(alignment: .leading, spacing: D.s2) {
                    SectionLabel(text: "Available steps")
                    Text("Click to add.").font(.system(size: 10)).foregroundStyle(.tertiary)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 5)],
                                  alignment: .leading, spacing: 5) {
                            ForEach(MethodBlock.allCases) { b in
                                Button { method.blocks.append(b) } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: b.icon).font(.system(size: 9))
                                        Text(b.label).font(D.small)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .help(b.blurb)
                            }
                        }
                    }
                    .frame(height: 260)
                }
                .frame(width: 280)

                VStack(alignment: .leading, spacing: D.s2) {
                    SectionLabel(text: "Your method")
                    Text("A step can appear more than once — screening twice is normal.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if method.blocks.isEmpty {
                                Text("Nothing yet. Add steps from the left, or start from a preset.")
                                    .font(D.small).foregroundStyle(.tertiary).padding(.top, D.s4)
                            }
                            ForEach(Array(method.blocks.enumerated()), id: \.offset) { i, b in
                                HStack(spacing: 6) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .frame(width: 18).foregroundStyle(.secondary)
                                    Image(systemName: b.icon).font(.system(size: 10))
                                    Text(b.label).font(D.small)
                                    Spacer()
                                    Button { move(i, -1) } label: { Image(systemName: "chevron.up") }
                                        .buttonStyle(.plain).disabled(i == 0)
                                    Button { move(i, 1) } label: { Image(systemName: "chevron.down") }
                                        .buttonStyle(.plain).disabled(i == method.blocks.count - 1)
                                    Button { method.blocks.remove(at: i) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.plain).foregroundStyle(Palette.rose)
                                }
                                .font(.system(size: 10))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(D.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(height: 260)
                }
                .frame(width: 320)
            }

            HStack {
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save method") {
                    if method.name.trimmingCharacters(in: .whitespaces).isEmpty { method.name = "My method" }
                    method.projectId = store.currentProjectId
                    method.isTemplate = false
                    // One method per review: replace whatever was there.
                    if method.id == 0, let existing = store.activeMethod { store.deleteMethod(existing.id) }
                    store.saveMethod(method)
                    done()
                }
                .buttonStyle(.borderedProminent)
                .disabled(method.blocks.isEmpty)
            }
        }
        .padding(D.s5).frame(width: 700)
    }

    private func move(_ i: Int, _ delta: Int) {
        let j = i + delta
        guard method.blocks.indices.contains(j) else { return }
        method.blocks.swapAt(i, j)
    }
}
