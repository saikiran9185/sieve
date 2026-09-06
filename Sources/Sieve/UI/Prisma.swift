import SwiftUI
import AppKit

/// The PRISMA 2020 flow diagram and reporting checklist, following the official templates
/// (Page MJ et al., BMJ 2021;372:n71). Four variants are supported, exactly as published:
/// new or updated review, with or without a second column for records found by other methods.
///
/// Everything the screening decisions can supply is computed. The counts PRISMA asks for that
/// no decision implies — registers, automation-tool removals, citation searching, a previous
/// version's studies — are typed into the boxes themselves.
struct PrismaView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator
    @State private var tab = 0
    @State private var drill: PrismaBox? = nil

    private var p: Store.Prisma { store.prisma }
    private var variant: PrismaVariant { store.prismaVariant }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch tab {
            case 0: flowTab
            case 1: ChecklistView()
            default: countsTab
            }
        }
        .background(D.canvas)
        .sheet(item: $drill) { box in DrillDownSheet(box: box) { drill = nil } }
    }

    private var toolbar: some View {
        Toolbar {
            Picker("", selection: $tab) {
                Text("Flow diagram").tag(0)
                Text("Reporting checklist").tag(1)
                Text("Counts").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 330)

            if tab == 0 {
                Menu {
                    ForEach(PrismaVariant.allCases) { v in
                        Button {
                            store.prismaVariant = v
                        } label: {
                            Text(v == variant ? "✓ \(v.label)" : v.label)
                        }
                    }
                } label: { Label(variant.label, systemImage: "square.on.square") }
                    .frame(width: 300)
                    .help(variant.blurb)
            }
            Spacer()
            Menu {
                Button("PNG image") { exportPNG() }
                Button("SVG (vector, scales for print)") { Exporters.exportPrismaSVG(store) }
                Button("Plain text with the counts") { Exporters.exportPrismaText(store) }
                Button("Reporting checklist (CSV)") { Exporters.exportChecklist(store) }
                Divider()
                Button("Everything in one folder…") { Exporters.exportEverything(store) }
                Button("Full review report as PDF") { Exporters.exportReportPDF(store) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .frame(width: 100)
        }
    }

    // MARK: Flow

    private var flowTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: D.s5) {
                warnings
                ScrollView(.horizontal, showsIndicators: true) {
                    diagram
                        .padding(D.s5)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: D.radiusL))
                        .hairlineBorder(D.radiusL)
                }
                Text("Every number is a button — click one to see exactly which records it counts. Boxes with a pencil hold figures PRISMA asks for that screening can't infer; type them in.")
                    .font(D.small).foregroundStyle(.secondary)
                Text(PrismaChecklist.citation).font(.system(size: 10)).foregroundStyle(.tertiary)
                sourceBreakdown
            }
            .padding(D.s5)
        }
    }

    @ViewBuilder
    private var warnings: some View {
        let untriaged = store.papers.filter { $0.stage == .identified || $0.stage == .screening }.count
        let noReason = store.papers.filter { $0.stage == .excludedEligibility && $0.excludeReason.isEmpty }.count
        let missing = store.missingFullTexts.count

        if missing > 0 {
            Card {
                VStack(alignment: .leading, spacing: D.s2) {
                    Label("\(missing) record\(missing == 1 ? "" : "s") passed screening with no full text",
                          systemImage: "doc.badge.ellipsis")
                        .font(D.heading).foregroundStyle(Palette.amber)
                    Text(store.strictRetrieval
                         ? "PRISMA is counting \(missing == 1 ? "it" : "them") under “reports not retrieved”, because there is no PDF on disk to show the report was obtained. Download or attach the files, or record the decision properly."
                         : "These are being counted as retrieved even though no PDF was obtained. Turn on the evidence rule in Settings to count them honestly.")
                        .font(D.small)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Show me which") { drill = .notRetrieved }.font(D.small)
                        Button("Mark them as not retrieved") {
                            let n = store.markMissingAsNotRetrieved()
                            store.flash("Moved \(n) records to “not retrieved”")
                        }
                        .font(D.small)
                        Spacer()
                        Toggle("Require a PDF as proof", isOn: Binding(
                            get: { store.strictRetrieval },
                            set: { store.strictRetrieval = $0 }))
                            .toggleStyle(.switch).font(D.small)
                    }
                }
            }
            .background(Palette.amber.opacity(0.07))
        }

        if untriaged > 0 || noReason > 0 {
            Card {
                VStack(alignment: .leading, spacing: D.s2) {
                    Label("This diagram isn't final yet", systemImage: "exclamationmark.triangle.fill")
                        .font(D.heading).foregroundStyle(Palette.amber)
                    if untriaged > 0 {
                        HStack {
                            Text("\(untriaged) record\(untriaged == 1 ? " has" : "s have") not been screened yet — they're counted as identified but sit in no downstream box.")
                                .font(D.small)
                            Spacer()
                            Button("Screen them") { nav.section = .screening }.font(D.small)
                        }
                    }
                    if noReason > 0 {
                        Text("\(noReason) full-text exclusion\(noReason == 1 ? "" : "s") ha\(noReason == 1 ? "s" : "ve") no recorded reason. PRISMA item 16b requires one per excluded report.")
                            .font(D.small)
                    }
                }
            }
            .background(Palette.amber.opacity(0.06))
        }
    }

    private var diagram: some View {
        HStack(alignment: .top, spacing: 34) {
            if variant.isUpdated { previousColumn }
            mainColumn
            if variant.hasOtherMethods { otherMethodsColumn }
        }
    }

    // Column 1 of the updated-review diagrams.
    private var previousColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnTitle("Previous studies")
            box("Studies included in previous version of review", n: p.previousStudies,
                editable: PrismaKey.previousStudies)
            Spacer().frame(height: 8)
            box("Reports of studies included in previous version", n: p.previousReports,
                editable: PrismaKey.previousReports)
            Spacer()
        }
        .frame(width: 250)
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            columnTitle(variant.isUpdated
                        ? "Identification of new studies via databases and registers"
                        : "Identification of studies via databases and registers")
            phaseRow("Identification") {
                HStack(alignment: .top, spacing: 30) {
                    box("Records identified from:", n: p.identified, box: .identified,
                        lines: [("Databases", p.fromDatabases, nil),
                                ("Registers", p.fromRegisters, PrismaKey.registers)])
                    arrowRight()
                    box("Records removed before screening:", n: p.removedBeforeScreening,
                        box: .removedBefore, muted: true,
                        lines: [("Duplicate records removed", p.duplicates, nil),
                                ("Marked ineligible by automation tools", p.automationRemoved, PrismaKey.automationRemoved),
                                ("Removed for other reasons", p.otherRemoved, PrismaKey.otherRemoved)])
                }
            }
            arrowDown()
            phaseRow("Screening") {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 30) {
                        box("Records screened", n: p.screened, box: .screened)
                        arrowRight()
                        box("Records excluded", n: p.excludedScreening, box: .excludedScreen, muted: true)
                    }
                    arrowDown()
                    HStack(alignment: .top, spacing: 30) {
                        box("Reports sought for retrieval", n: p.sought, box: .sought)
                        arrowRight()
                        box("Reports not retrieved", n: p.notRetrieved, box: .notRetrieved, muted: true)
                    }
                    arrowDown()
                    HStack(alignment: .top, spacing: 30) {
                        box("Reports assessed for eligibility", n: p.assessed, box: .assessed)
                        arrowRight()
                        box("Reports excluded:", n: p.excludedEligibility, box: .excludedFull, muted: true,
                            lines: p.exclusionReasons.map { ($0.0, $0.1, nil) })
                    }
                }
            }
            arrowDown()
            phaseRow("Included") {
                box(variant.isUpdated ? "New studies included in review" : "Studies included in review",
                    n: p.includedStudies, box: .included, highlight: true,
                    lines: [("Reports of included studies", p.includedReports, nil)])
            }
            if variant.isUpdated {
                arrowDown()
                box("Total studies included in review", n: p.totalStudies, highlight: true,
                    lines: [("Reports of total included studies", p.totalReports, nil)])
            }
        }
        .frame(width: 560)
    }

    private var otherMethodsColumn: some View {
        VStack(spacing: 0) {
            columnTitle(variant.isUpdated
                        ? "Identification of new studies via other methods"
                        : "Identification of studies via other methods")
            box("Records identified from:", n: p.otherIdentified,
                lines: [("Websites", p.otherWebsites, PrismaKey.websites),
                        ("Organisations", p.otherOrganisations, PrismaKey.organisations),
                        ("Citation searching", p.otherCitation, PrismaKey.citationSearching)])
            arrowDown()
            HStack(alignment: .top, spacing: 24) {
                box("Reports sought for retrieval", n: p.otherSought, editable: PrismaKey.otherSought)
                box("Reports not retrieved", n: p.otherNotRetrieved,
                    editable: PrismaKey.otherNotRetrieved, muted: true)
            }
            arrowDown()
            HStack(alignment: .top, spacing: 24) {
                box("Reports assessed for eligibility", n: p.otherAssessed, editable: PrismaKey.otherAssessed)
                box("Reports excluded", n: p.otherExcluded, editable: PrismaKey.otherExcluded, muted: true)
            }
            arrowDown()
            box("Studies from other methods included", n: p.otherIncluded,
                editable: PrismaKey.otherIncluded, highlight: true)
        }
        .frame(width: 420)
    }

    private func columnTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: "#111827"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(hex: "#E5E7EB"))
            .overlay(Rectangle().stroke(Color(hex: "#9CA3AF"), lineWidth: 1))
            .padding(.bottom, 10)
    }

    private func phaseRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color(hex: "#6B7280"))
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 16, height: 74)
            content()
        }
    }

    /// One box on the diagram. `box` makes the total clickable; `editable` and the per-line
    /// keys make individual figures typeable.
    private func box(_ title: String, n: Int, box drillBox: PrismaBox? = nil,
                     editable: String? = nil, muted: Bool = false, highlight: Bool = false,
                     lines: [(String, Int, String?)] = []) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color(hex: "#111827"))
                .fixedSize(horizontal: false, vertical: true)

            if lines.isEmpty {
                countControl(n, drillBox: drillBox, editable: editable, highlight: highlight)
            } else {
                countControl(n, drillBox: drillBox, editable: nil, highlight: highlight)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 3) {
                            Text(line.0).font(.system(size: 9.5)).foregroundStyle(Color(hex: "#6B7280"))
                            if let key = line.2 {
                                CountField(key: key, value: line.1)
                            } else {
                                Text("(n = \(line.1))").font(.system(size: 9.5))
                                    .foregroundStyle(Color(hex: "#374151"))
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(width: 250, alignment: .topLeading)
        .background(highlight ? Color(hex: "#DCFCE7") : (muted ? Color(hex: "#F9FAFB") : Color.white))
        .overlay(Rectangle().stroke(Color(hex: highlight ? "#16A34A" : "#9CA3AF"),
                                    lineWidth: highlight ? 1.5 : 1))
    }

    @ViewBuilder
    private func countControl(_ n: Int, drillBox: PrismaBox?, editable: String?, highlight: Bool) -> some View {
        if let key = editable {
            HStack(spacing: 3) {
                Text("(n =").font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "#374151"))
                CountField(key: key, value: n, large: true)
                Text(")").font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "#374151"))
            }
        } else if let b = drillBox {
            Button { drill = b } label: {
                HStack(spacing: 3) {
                    Text("(n = \(n))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(highlight ? Color(hex: "#166534") : Color(hex: "#1D4ED8"))
                        .underline()
                    Image(systemName: "arrow.up.right.square").font(.system(size: 8))
                        .foregroundStyle(Color(hex: "#1D4ED8"))
                }
            }
            .buttonStyle(.plain)
            .help("See the records behind this number")
        } else {
            Text("(n = \(n))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(highlight ? Color(hex: "#166534") : Color(hex: "#374151"))
        }
    }

    private func arrowDown() -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: "#9CA3AF")).frame(width: 1, height: 20)
            Triangle().fill(Color(hex: "#9CA3AF")).frame(width: 8, height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    private func arrowRight() -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(hex: "#9CA3AF")).frame(width: 22, height: 1)
            Triangle().rotation(.degrees(90)).fill(Color(hex: "#9CA3AF")).frame(width: 6, height: 8)
        }
        .padding(.top, 20)
    }

    // MARK: Counts tab

    private var countsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: D.s4) {
                Text("Figures PRISMA asks for that screening can't infer")
                    .font(D.heading)
                Text("Everything else on the diagram is counted from your decisions. These are the numbers only you know — how many records came from a register rather than a database, what an automation tool removed, what you found by chasing reference lists.")
                    .font(D.small).foregroundStyle(.secondary)

                group("Identification", [
                    (PrismaKey.registers, "Records identified from registers", "Trial or study registers, as opposed to bibliographic databases."),
                    (PrismaKey.automationRemoved, "Marked ineligible by automation tools", "Removed before a human screened them."),
                    (PrismaKey.otherRemoved, "Removed before screening for other reasons", "Anything else dropped before screening began."),
                    (PrismaKey.automationExcluded, "Excluded at screening by automation", "PRISMA asks you to separate human and automated exclusions."),
                ])

                group("Other methods (used by the v2 diagrams)", [
                    (PrismaKey.websites, "Records identified from websites", ""),
                    (PrismaKey.organisations, "Records identified from organisations", ""),
                    (PrismaKey.citationSearching, "Records identified by citation searching", "Backward and forward reference chasing."),
                    (PrismaKey.otherSought, "Reports sought for retrieval", ""),
                    (PrismaKey.otherNotRetrieved, "Reports not retrieved", ""),
                    (PrismaKey.otherAssessed, "Reports assessed for eligibility", ""),
                    (PrismaKey.otherExcluded, "Reports excluded", ""),
                    (PrismaKey.otherIncluded, "Studies included from other methods", ""),
                ])

                group("Previous version (used by the updated-review diagrams)", [
                    (PrismaKey.previousStudies, "Studies included in the previous version", ""),
                    (PrismaKey.previousReports, "Reports of those studies", ""),
                ])

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Studies versus reports")
                        Text("PRISMA counts studies and the reports of them separately, because one study can be published across several papers. Sieve treats each record as one report of one study unless you say otherwise — open a paper's details to set how many reports it has.")
                            .font(D.small).foregroundStyle(.secondary)
                        Text("Currently: \(p.includedStudies) studies, \(p.includedReports) reports.")
                            .font(D.small.weight(.medium))
                    }
                }
            }
            .padding(D.s5).frame(maxWidth: 780, alignment: .leading)
        }
    }

    private func group(_ title: String, _ rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: D.s2) {
            SectionLabel(text: title)
            Card {
                VStack(alignment: .leading, spacing: D.s3) {
                    ForEach(rows, id: \.0) { key, label, hint in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(label).font(D.body)
                                if !hint.isEmpty {
                                    Text(hint).font(D.small).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Stepper(value: Binding(
                                get: { store.prismaCount(key) },
                                set: { store.setPrismaCount(key, $0) }), in: 0...100000) {
                                Text("\(store.prismaCount(key))")
                                    .font(D.body.monospacedDigit())
                                    .frame(width: 46, alignment: .trailing)
                            }
                            .frame(width: 110)
                        }
                    }
                }
            }
        }
    }

    private var sourceBreakdown: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            SectionLabel(text: "Where the records came from")
            Card {
                VStack(alignment: .leading, spacing: D.s2) {
                    ForEach(p.perSource, id: \.0) { src, n in
                        HStack {
                            Text(src).font(D.body)
                            Spacer()
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Palette.accent.opacity(0.35))
                                    .frame(width: geo.size.width * CGFloat(n) / CGFloat(max(p.identified, 1)),
                                           height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(width: 200, height: 14)
                            Text("\(n)").font(D.body.monospacedDigit()).frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }

            SectionLabel(text: "Search history")
            Card {
                let runs = store.searchRuns()
                if runs.isEmpty {
                    Text("No database searches recorded yet. PRISMA item 7 asks for the full search strategy for every source, with the date each was last searched — Sieve logs that here automatically.")
                        .font(D.small).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: D.s2) {
                        ForEach(Array(runs.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("“\(r.query)”").font(D.body)
                                Text("\(r.providers) · \(r.results) results · \(r.imported) added · \(r.at.formatted(date: .abbreviated, time: .shortened))")
                                    .font(D.small).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func exportPNG() {
        let renderer = ImageRenderer(content:
            diagram.padding(28).background(Color.white).environmentObject(store))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            store.flash("Could not render the diagram"); return
        }
        Exporters.save(data: png, suggested: "PRISMA-flow.png", store: store)
    }
}

/// A number on the diagram you can type into directly.
struct CountField: View {
    let key: String
    let value: Int
    var large = false
    @EnvironmentObject var store: Store
    @State private var text = ""
    @State private var editing = false

    var body: some View {
        HStack(spacing: 2) {
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .font(.system(size: large ? 12 : 10, design: .monospaced))
                    .onSubmit { commit() }
                Button("↩") { commit() }.buttonStyle(.plain).font(.system(size: 9))
            } else {
                Button {
                    text = String(value); editing = true
                } label: {
                    HStack(spacing: 2) {
                        Text(large ? "\(value)" : "(n = \(value))")
                            .font(.system(size: large ? 13 : 9.5,
                                          weight: large ? .semibold : .regular,
                                          design: large ? .rounded : .default))
                            .foregroundStyle(Color(hex: "#374151"))
                        Image(systemName: "pencil").font(.system(size: 7))
                            .foregroundStyle(Color(hex: "#9CA3AF"))
                    }
                }
                .buttonStyle(.plain)
                .help("Type this figure in — PRISMA asks for it and screening can't infer it")
            }
        }
    }

    private func commit() {
        store.setPrismaCount(key, Int(text) ?? 0)
        editing = false
    }
}

/// Clicking a number opens the records behind it — provenance for every figure reported.
struct DrillDownSheet: View {
    let box: PrismaBox
    var done: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator

    private var papers: [Paper] { store.papers(forPrismaBox: box) }

    private var title: String {
        switch box {
        case .identified: return "Records identified"
        case .removedBefore: return "Records removed before screening"
        case .screened: return "Records screened"
        case .excludedScreen: return "Records excluded at title and abstract"
        case .sought: return "Reports sought for retrieval"
        case .notRetrieved: return "Reports not retrieved"
        case .assessed: return "Reports assessed for eligibility"
        case .excludedFull: return "Reports excluded after reading"
        case .included: return "Studies included in the review"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(D.title)
                    Text("\(papers.count) record\(papers.count == 1 ? "" : "s")")
                        .font(D.small).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(D.s4)
            Divider()
            if papers.isEmpty {
                EmptyState(icon: "tray", title: "No records here yet", message: "")
                    .frame(height: 200)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(papers) { p in
                            HStack(alignment: .top, spacing: D.s3) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.title).font(D.small.weight(.medium)).lineLimit(2)
                                    Text("\(p.authorLine) · \(p.year.map(String.init) ?? "n.d.") · \(p.sourceDB)")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                    if !p.excludeReason.isEmpty {
                                        // The reason is the point of the drill-down for the
                                        // exclusion boxes: PRISMA 16b wants it reported.
                                        Chip(text: p.excludeReason, color: Palette.rose)
                                    }
                                }
                                Spacer()
                                StageBadge(stage: p.stage)
                                Button { nav.read(p.id); done() } label: { Image(systemName: "book") }
                                    .buttonStyle(.plain).foregroundStyle(Palette.accent)
                            }
                            .padding(.horizontal, D.s4).padding(.vertical, D.s2 + 2)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 700, height: 520)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
