import SwiftUI
import AppKit

/// Everything the assistant produced, and what was decided about it.
///
/// The premise: you cannot out-run a model, so the value is not in producing claims faster —
/// it is in being the place where a claim gets checked against its source and the checking is
/// recorded. This screen is that record, and the queue at the top of it is the work.
struct AITrailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var assistant: Assistant
    @State private var filter: Filter = .pending
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case pending = "Needs checking", all = "Everything", accepted = "Accepted"
        case rejected = "Rejected", edited = "Edited"
        var id: String { rawValue }
    }

    private var events: [AIEvent] {
        store.aiEvents.filter { e in
            let passes: Bool
            switch filter {
            case .pending: passes = e.outcome == .pending && e.kind.needsAdjudication
            case .all: passes = true
            case .accepted: passes = e.outcome == .accepted
            case .rejected: passes = e.outcome == .rejected
            case .edited: passes = e.outcome == .edited
            }
            guard passes else { return false }
            guard !search.isEmpty else { return true }
            return e.said.localizedCaseInsensitiveContains(search)
                || e.asked.localizedCaseInsensitiveContains(search)
                || (store.paper(e.subjectId)?.title.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if store.aiEvents.isEmpty { empty } else { content }
        }
        .background(D.canvas)
    }

    private var toolbar: some View {
        Toolbar {
            Text("AI trail").font(D.body.weight(.medium))
            let s = store.aiSummary
            if s.pending > 0 {
                Chip(text: "\(s.pending) unchecked", color: Palette.amber,
                     icon: "exclamationmark.triangle.fill")
            } else if s.everUsed {
                Chip(text: "all checked", color: Palette.emerald, icon: "checkmark.seal.fill")
            }
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 420)
            SearchField(placeholder: "Search what it said", text: $search).frame(width: 200)
            Spacer()
            Menu {
                Button("AI-use disclosure (Markdown)") { Exporters.exportAIDisclosure(store) }
                Button("Full trail as CSV") { Exporters.exportAITrail(store) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .frame(width: 100)
        }
    }

    private var empty: some View {
        EmptyState(icon: "shield.lefthalf.filled",
                   title: Assistant.isAvailable && assistant.enabled
                        ? "The assistant hasn't been used in this review"
                        : "The assistant is switched off",
                   message: "Anything it suggests is recorded here — what was asked, what it said, and whether you accepted, edited or rejected it. Nothing it produces counts as checked until you say so, and the disclosure export states exactly that.")
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: D.s3) {
                if filter == .pending && events.isEmpty {
                    Card {
                        HStack(spacing: D.s3) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20)).foregroundStyle(Palette.emerald)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Every AI suggestion in this review has been adjudicated")
                                    .font(D.body.weight(.medium))
                                Text("The disclosure export can state that without qualification.")
                                    .font(D.small).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .background(Palette.emerald.opacity(0.06))
                }
                ForEach(events) { event in row(event) }
            }
            .padding(D.s4)
        }
    }

    private func row(_ e: AIEvent) -> some View {
        Card(padding: D.s3) {
            VStack(alignment: .leading, spacing: D.s2) {
                HStack(spacing: 6) {
                    Chip(text: e.kind.label, color: Palette.violet, icon: e.kind.icon)
                    Chip(text: e.outcome.label, color: e.outcome.color, icon: e.outcome.icon)
                    if !e.confidence.isEmpty {
                        Chip(text: "\(e.confidence) confidence", color: Palette.slate)
                    }
                    Spacer()
                    Text(e.at.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }

                if let p = store.paper(e.subjectId), e.subjectKind == "paper" || e.subjectKind == "cell" {
                    Button { nav.read(p.id) } label: {
                        HStack(spacing: 4) {
                            Text(p.citeKey).font(D.mono).foregroundStyle(.tertiary)
                            Text(p.title).font(D.small).lineLimit(1)
                            if e.subjectKind == "cell",
                               let c = store.columns.first(where: { $0.id == e.columnId }) {
                                Text("· \(c.name)").font(D.small).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(Palette.accent)
                }

                Text(e.said)
                    .font(D.serif)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(.leading, D.s2)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Palette.violet.opacity(0.5)).frame(width: 3)
                    }

                if !e.model.isEmpty {
                    Text("produced by \(e.model)")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }

                if e.outcome == .pending && e.kind.needsAdjudication {
                    HStack(spacing: 6) {
                        Text("Checked against the source?")
                            .font(D.small).foregroundStyle(.secondary)
                        Button("It's right") { store.resolveAI(e.id, .accepted) }
                            .buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
                        Button("I changed it") { store.resolveAI(e.id, .edited) }
                            .buttonStyle(.bordered).controlSize(.small).tint(Palette.emerald)
                        Button("It's wrong") { store.resolveAI(e.id, .rejected) }
                            .buttonStyle(.bordered).controlSize(.small).tint(Palette.rose)
                        Button("Didn't use it") { store.resolveAI(e.id, .unused) }
                            .buttonStyle(.plain).font(D.small).foregroundStyle(.secondary)
                    }
                } else if !e.humanNote.isEmpty {
                    Text(e.humanNote).font(D.small).foregroundStyle(.secondary)
                }
            }
        }
    }
}
