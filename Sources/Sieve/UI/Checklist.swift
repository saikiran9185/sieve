import SwiftUI
import AppKit

/// The PRISMA 2020 reporting checklist, all 27 items (42 with sub-items), tracked per review.
/// It is the other half of PRISMA: the flow diagram says what happened to the records, the
/// checklist says whether the write-up reports it. Items Sieve can see the answer to are
/// pre-answered, with the evidence quoted, so you are only judging the rest.
struct ChecklistView: View {
    @EnvironmentObject var store: Store
    @State private var filter: Filter = .all
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", todo = "Not done", done = "Done", na = "N/A"
        var id: String { rawValue }
    }

    private var items: [ChecklistItem] {
        PrismaChecklist.items.filter { item in
            let state = store.checklist[item.id]?.state ?? "todo"
            let passesFilter: Bool
            switch filter {
            case .all: passesFilter = true
            case .todo: passesFilter = state == "todo"
            case .done: passesFilter = state == "done"
            case .na: passesFilter = state == "na"
            }
            let passesSearch = search.isEmpty
                || item.text.localizedCaseInsensitiveContains(search)
                || item.topic.localizedCaseInsensitiveContains(search)
                || item.id == search
            return passesFilter && passesSearch
        }
    }

    private var doneCount: Int {
        PrismaChecklist.items.filter { (store.checklist[$0.id]?.state ?? "todo") != "todo" }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections, id: \.self) { section in
                        SwiftUI.Section {
                            ForEach(items.filter { $0.section == section }) { item in
                                row(item)
                                Divider()
                            }
                        } header: {
                            Text(section.uppercased())
                                .font(D.label).tracking(0.8)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, D.s4).padding(.vertical, 6)
                                .background(.bar)
                        }
                    }
                }
            }
        }
    }

    private var sections: [String] {
        var seen: [String] = []
        for i in items where !seen.contains(i.section) { seen.append(i.section) }
        return seen
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRISMA 2020 reporting checklist").font(D.heading)
                    Text("\(doneCount) of \(PrismaChecklist.items.count) items answered")
                        .font(D.small).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(doneCount), total: Double(PrismaChecklist.items.count))
                    .frame(width: 160)
                Spacer()
                SearchField(placeholder: "Find an item", text: $search).frame(width: 200)
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                Link(destination: URL(string: PrismaChecklist.statement)!) {
                    Label("The statement", systemImage: "arrow.up.forward.square")
                }
                .font(D.small)
                Link(destination: URL(string: PrismaChecklist.elaboration)!) {
                    Label("How to answer each item", systemImage: "book")
                }
                .font(D.small)
                .help("PRISMA 2020 explanation and elaboration — BMJ 2021;372:n160")
            }
            Text("Mark where in your manuscript each item is reported. “Where it is reported” is the column the journal will ask you to submit.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(D.s4)
    }

    private func row(_ item: ChecklistItem) -> some View {
        let state = store.checklist[item.id]?.state ?? "todo"
        let location = store.checklist[item.id]?.location ?? ""
        return HStack(alignment: .top, spacing: D.s3) {
            Text(item.id)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.topic).font(D.body.weight(.medium))
                Text(item.text)
                    .font(D.small).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Where Sieve already holds the answer, it says so instead of asking.
                if let hint = evidenceFor(item) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10)).foregroundStyle(Palette.emerald)
                        Text(hint).font(.system(size: 10.5)).foregroundStyle(Palette.emerald)
                    }
                }

                TextField("Where it is reported — e.g. “Methods, p.4” or “Table 2”",
                          text: Binding(
                            get: { location },
                            set: { store.setChecklist(item.id, state: state, location: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(D.small)
                    .frame(maxWidth: 420)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { state },
                set: { store.setChecklist(item.id, state: $0, location: location) })) {
                Text("To do").tag("todo")
                Text("Done").tag("done")
                Text("N/A").tag("na")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 170)
        }
        .padding(.horizontal, D.s4).padding(.vertical, D.s3)
        .background(state == "done" ? Palette.emerald.opacity(0.05)
                    : (state == "na" ? Color.secondary.opacity(0.04) : Color.clear))
    }

    /// Items the app can answer from the review data itself.
    private func evidenceFor(_ item: ChecklistItem) -> String? {
        let p = store.prisma
        switch item.id {
        case "4":
            let q = store.project?.question ?? ""
            return q.isEmpty ? nil : "Sieve holds your review question."
        case "5":
            let inc = store.project?.inclusionCriteria ?? ""
            let exc = store.project?.exclusionCriteria ?? ""
            return (inc.isEmpty && exc.isEmpty) ? nil : "Your inclusion and exclusion criteria are recorded."
        case "6":
            let n = store.searchRuns().count
            return n == 0 ? nil : "\(n) searches logged with their databases and dates."
        case "7":
            let runs = store.searchRuns()
            return runs.isEmpty ? nil : "Full search strings are in the search history, exportable."
        case "16a":
            return p.identified == 0 ? nil : "The flow diagram is generated from your decisions."
        case "16b":
            let n = p.exclusionReasons.reduce(0) { $0 + $1.1 }
            return n == 0 ? nil : "\(n) full-text exclusions with reasons recorded."
        case "17":
            return store.included.isEmpty ? nil
                : "\(store.included.count) included studies with characteristics in the matrix."
        case "27":
            return "Sieve exports the data, the matrix and the highlights as files you can deposit."
        default:
            return nil
        }
    }
}
