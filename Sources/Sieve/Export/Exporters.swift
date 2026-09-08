import Foundation
import AppKit

/// Everything leaves the app in a form a thesis or a supervisor can use.
@MainActor
enum Exporters {

    static func save(data: Data, suggested: String, store: Store) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.directoryURL = Library.exportDir
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            store.flash("Saved to \(url.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { store.flash("Could not save: \(error.localizedDescription)") }
    }

    static func save(text: String, suggested: String, store: Store) {
        save(data: Data(text.utf8), suggested: suggested, store: store)
    }

    static func csvEscape(_ s: String) -> String {
        let clean = s.replacingOccurrences(of: "\"", with: "\"\"")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(clean)\""
    }

    // MARK: Papers

    static func exportPapersCSV(_ store: Store, only stage: Stage?) {
        let rows = stage == nil ? store.papers : store.papers.filter { $0.stage == stage! }
        save(text: papersCSV(store, rows),
             suggested: stage == .included ? "included-papers.csv" : "library.csv", store: store)
    }

    static func papersCSV(_ store: Store, _ rows: [Paper]) -> String {
        var out = ["Citation key,Title,Authors,Year,Venue,DOI,Stage,Exclusion reason,Source database,Found by search,Open access,Cited by,Added,PDF,Highlights,Folder,Conclusion,SDG,Notes"]
        for p in rows {
            out.append([
                p.citeKey, p.title, p.authors.joined(separator: "; "),
                p.year.map(String.init) ?? "", p.venue, p.doi,
                p.stage.label, p.excludeReason, p.sourceDB, p.sourceQuery,
                p.oaStatus, String(p.citedBy),
                p.addedAt.formatted(date: .numeric, time: .omitted),
                p.hasPDF ? "yes" : "no",
                String(store.evidence(forPaper: p.id).count),
                store.folder(p.folderId)?.name ?? "",
                p.conclusion,
                p.sdgs.joined(separator: "; "),
                p.notes
            ].map(csvEscape).joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    static func exportBibTeX(_ store: Store) {
        save(text: bibText(store, store.included), suggested: "included.bib", store: store)
    }

    /// RIS is what Zotero, Mendeley and EndNote all read. Sieve could already import it;
    /// without an exporter a review could go in but never come back out to a reference
    /// manager, which is where most people write from.
    static func risText(_ store: Store, _ papers: [Paper]) -> String {
        var out = ""
        for p in papers {
            out += "TY  - \(risType(p))\n"
            for author in p.authors { out += "AU  - \(risAuthor(author))\n" }
            out += "TI  - \(p.title)\n"
            if let y = p.year { out += "PY  - \(y)\n" }
            if !p.pubDate.isEmpty { out += "DA  - \(p.pubDate)\n" }
            if !p.venue.isEmpty { out += "JO  - \(p.venue)\n" }
            if !p.doi.isEmpty { out += "DO  - \(p.doi)\n" }
            if !p.abstract.isEmpty {
                out += "AB  - \(p.abstract.replacingOccurrences(of: "\n", with: " "))\n"
            }
            for k in p.keywords { out += "KW  - \(k)\n" }
            for g in p.sdgs { out += "KW  - SDG: \(g)\n" }
            if !p.url.isEmpty { out += "UR  - \(p.url)\n" }
            if p.hasPDF { out += "L1  - \(p.pdfPath)\n" }
            // Your own work travels with the record rather than being left behind.
            var notes: [String] = []
            if !p.conclusion.isEmpty { notes.append("Conclusion: \(p.conclusion)") }
            if !p.notes.isEmpty { notes.append(p.notes) }
            if !p.excludeReason.isEmpty { notes.append("Excluded: \(p.excludeReason)") }
            let highlights = store.evidence(forPaper: p.id)
            if !highlights.isEmpty {
                notes.append(highlights.map { "[p.\($0.page + 1)] \($0.quote)" }.joined(separator: " | "))
            }
            if !notes.isEmpty {
                out += "N1  - \(notes.joined(separator: " — ").replacingOccurrences(of: "\n", with: " "))\n"
            }
            out += "ER  - \n\n"
        }
        return out
    }

    private static func risType(_ p: Paper) -> String {
        switch p.sourceType {
        case .book: return "BOOK"
        case .chapter: return "CHAP"
        case .report: return "RPRT"
        case .thesis: return "THES"
        case .website: return "ELEC"
        case .dataset: return "DATA"
        case .video: return "VIDEO"
        case .interview: return "PCOMM"
        default: return p.docType.lowercased().contains("preprint") ? "MANSCPT" : "JOUR"
        }
    }

    /// RIS expects "Family, Given".
    private static func risAuthor(_ name: String) -> String {
        if name.contains(",") { return name }
        let parts = name.split(separator: " ")
        guard parts.count > 1, let family = parts.last else { return name }
        return "\(family), \(parts.dropLast().joined(separator: " "))"
    }

    static func exportRIS(_ store: Store, _ papers: [Paper]) {
        save(text: risText(store, papers), suggested: "sieve-export.ris", store: store)
    }

    static func bibText(_ store: Store, _ papers: [Paper]) -> String {
        var out = ""
        for p in papers {
            out += "@article{\(p.citeKey),\n"
            out += "  title = {\(p.title)},\n"
            if !p.authors.isEmpty { out += "  author = {\(p.authors.joined(separator: " and "))},\n" }
            if let y = p.year { out += "  year = {\(y)},\n" }
            if !p.venue.isEmpty { out += "  journal = {\(p.venue)},\n" }
            if !p.doi.isEmpty { out += "  doi = {\(p.doi)},\n" }
            if !p.url.isEmpty { out += "  url = {\(p.url)},\n" }
            out += "}\n\n"
        }
        return out
    }

    // MARK: Evidence

    static func exportEvidenceCSV(_ store: Store, _ items: [Evidence]) {
        save(text: evidenceCSV(store, items), suggested: "evidence.csv", store: store)
    }

    static func evidenceCSV(_ store: Store, _ items: [Evidence]) -> String {
        var out = ["Quote,My note,Categories,Page,Paper,Authors,Year,DOI,Source database,Source link,Date highlighted,AI generated"]
        for e in items {
            let p = store.paper(e.paperId)
            let tags = e.tagIds.compactMap { store.tag($0)?.name }.joined(separator: "; ")
            let page: String = e.page >= 0 ? String(e.page + 1) : ""
            let title: String = p?.title ?? ""
            let authors: String = p?.authors.joined(separator: "; ") ?? ""
            let year: String = p?.year.map(String.init) ?? ""
            let doi: String = p?.doi ?? ""
            let source: String = p?.sourceDB ?? ""
            var link: String = ""
            if let p { link = p.doi.isEmpty ? p.url : "https://doi.org/\(p.doi)" }
            let when: String = e.createdAt.formatted(date: .numeric, time: .omitted)
            let ai: String = e.aiGenerated ? "yes" : "no"
            let fields: [String] = [e.quote, e.note, tags, page, title, authors,
                                    year, doi, source, link, when, ai]
            out.append(fields.map(csvEscape).joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    static func exportEvidenceMarkdown(_ store: Store, _ items: [Evidence]) {
        save(text: evidenceMarkdown(store, items), suggested: "evidence.md", store: store)
    }

    static func evidenceMarkdown(_ store: Store, _ items: [Evidence]) -> String {
        var out = "# Evidence — \(store.project?.name ?? "Review")\n\n"
        if let q = store.project?.question, !q.isEmpty { out += "**Review question:** \(q)\n\n" }
        out += "_\(items.count) highlights, exported \(Date().formatted(date: .long, time: .omitted))_\n\n"

        for tag in store.tags {
            let group = items.filter { $0.tagIds.contains(tag.id) }
            guard !group.isEmpty else { continue }
            out += "## \(tag.name)\n"
            if !tag.detail.isEmpty { out += "_\(tag.detail)_\n\n" }
            for e in group {
                guard let p = store.paper(e.paperId) else { continue }
                out += "> \(e.quote)\n>\n> — \(p.authorLine), \(p.year.map(String.init) ?? "n.d."), p.\(e.page + 1)"
                if !p.doi.isEmpty { out += " · [doi](https://doi.org/\(p.doi))" }
                out += "\n\n"
                if !e.note.isEmpty { out += "\(e.note)\n\n" }
            }
        }

        let untagged = items.filter { $0.tagIds.isEmpty }
        if !untagged.isEmpty {
            out += "## Untagged\n"
            for e in untagged {
                let p = store.paper(e.paperId)
                out += "> \(e.quote)\n>\n> — \(p?.authorLine ?? ""), p.\(e.page + 1)\n\n"
            }
        }

        out += "\n---\n\n## References\n\n"
        for p in store.papers where items.contains(where: { $0.paperId == p.id }) {
            out += "- \(p.reference)\n"
        }
        return out
    }

    // MARK: Matrix

    static func matrixGrid(_ store: Store, rows: [Paper]) -> [[String]] {
        var grid: [[String]] = [["Paper", "Authors", "Year", "Source"] + store.columns.map(\.name)]
        for p in rows {
            var line = [p.title, p.authors.joined(separator: "; "), p.year.map(String.init) ?? "", p.sourceDB]
            for c in store.columns {
                let cell = store.cell(p.id, c.id)
                line.append(cell.value + (cell.aiGenerated && !cell.value.isEmpty ? " [AI draft]" : ""))
            }
            grid.append(line)
        }
        return grid
    }

    static func exportMatrixCSV(_ store: Store, rows: [Paper]) {
        let text = matrixGrid(store, rows: rows)
            .map { $0.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n")
        save(text: text, suggested: "review-matrix.csv", store: store)
    }

    static func copyMatrixTSV(_ store: Store, rows: [Paper]) {
        let text = matrixGrid(store, rows: rows)
            .map { $0.map { $0.replacingOccurrences(of: "\t", with: " ")
                             .replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t") }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.flash("Matrix copied — paste straight into Excel, Numbers or Sheets")
    }

    static func exportMatrixMarkdown(_ store: Store, rows: [Paper]) {
        let grid = matrixGrid(store, rows: rows)
        guard let header = grid.first else { return }
        var out = "# Literature review matrix — \(store.project?.name ?? "")\n\n"
        if let q = store.project?.question, !q.isEmpty { out += "**Question:** \(q)\n\n" }
        out += "| " + header.joined(separator: " | ") + " |\n"
        out += "|" + header.map { _ in " --- " }.joined(separator: "|") + "|\n"
        for row in grid.dropFirst() {
            out += "| " + row.map { $0.replacingOccurrences(of: "|", with: "\\|")
                                     .replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: " | ") + " |\n"
        }
        save(text: out, suggested: "review-matrix.md", store: store)
    }

    // MARK: PRISMA

    static func prismaLines(_ store: Store) -> [String] {
        let p = store.prisma
        let v = store.prismaVariant
        var out: [String] = []
        out.append("PRISMA 2020 flow — \(store.project?.name ?? "Review")")
        out.append("Diagram: \(v.label)")
        if let q = store.project?.question, !q.isEmpty { out.append("Review question: \(q)") }
        out.append("Generated \(Date().formatted(date: .long, time: .shortened))")
        out.append("")

        if v.isUpdated {
            out.append("PREVIOUS STUDIES")
            out.append("  Studies included in previous version of review (n = \(p.previousStudies))")
            out.append("  Reports of studies included in previous version (n = \(p.previousReports))")
            out.append("")
        }

        out.append("IDENTIFICATION")
        out.append("  Records identified from (n = \(p.identified)):")
        out.append("      Databases (n = \(p.fromDatabases))")
        out.append("      Registers (n = \(p.fromRegisters))")
        for (src, n) in p.perSource { out.append("          \(src): \(n)") }
        out.append("  Records removed before screening (n = \(p.removedBeforeScreening)):")
        out.append("      Duplicate records removed (n = \(p.duplicates))")
        out.append("      Marked ineligible by automation tools (n = \(p.automationRemoved))")
        out.append("      Removed for other reasons (n = \(p.otherRemoved))")
        out.append("")

        out.append("SCREENING")
        out.append("  Records screened (n = \(p.screened))")
        out.append("  Records excluded (n = \(p.excludedScreening))")
        out.append("  Reports sought for retrieval (n = \(p.sought))")
        out.append("  Reports not retrieved (n = \(p.notRetrieved))")
        out.append("  Reports assessed for eligibility (n = \(p.assessed))")
        out.append("  Reports excluded (n = \(p.excludedEligibility)):")
        for (r, n) in p.exclusionReasons { out.append("      \(r) (n = \(n))") }
        out.append("")

        if v.hasOtherMethods {
            out.append("IDENTIFICATION OF STUDIES VIA OTHER METHODS")
            out.append("  Records identified from (n = \(p.otherIdentified)):")
            out.append("      Websites (n = \(p.otherWebsites))")
            out.append("      Organisations (n = \(p.otherOrganisations))")
            out.append("      Citation searching (n = \(p.otherCitation))")
            out.append("  Reports sought for retrieval (n = \(p.otherSought))")
            out.append("  Reports not retrieved (n = \(p.otherNotRetrieved))")
            out.append("  Reports assessed for eligibility (n = \(p.otherAssessed))")
            out.append("  Reports excluded (n = \(p.otherExcluded))")
            out.append("")
        }

        out.append("INCLUDED")
        out.append("  \(v.isUpdated ? "New studies" : "Studies") included in review (n = \(p.includedStudies))")
        out.append("  Reports of included studies (n = \(p.includedReports))")
        if v.isUpdated {
            out.append("  Total studies included in review (n = \(p.totalStudies))")
            out.append("  Reports of total included studies (n = \(p.totalReports))")
        }
        out.append("")
        out.append("SEARCH HISTORY")
        for r in store.searchRuns() {
            out.append("  \"\(r.query)\" — \(r.providers) — \(r.results) results, \(r.imported) added — \(r.at.formatted(date: .abbreviated, time: .shortened))")
        }
        out.append("")
        out.append("Source: " + PrismaChecklist.citation)
        return out
    }

    static func checklistCSV(_ store: Store) -> String {
        var out = ["Section,Item,Topic,Checklist item,Status,Location where item is reported"]
        for item in PrismaChecklist.items {
            let entry = store.checklist[item.id]
            let state = entry?.state ?? "todo"
            out.append([item.section, item.id, item.topic, item.text,
                        state == "done" ? "Reported" : (state == "na" ? "Not applicable" : "Not yet"),
                        entry?.location ?? ""].map(csvEscape).joined(separator: ","))
        }
        out.append("")
        out.append(csvEscape("From: " + PrismaChecklist.citation))
        return out.joined(separator: "\n")
    }

    static func exportChecklist(_ store: Store) {
        save(text: checklistCSV(store), suggested: "PRISMA-2020-checklist.csv", store: store)
    }

    static func exportPrismaText(_ store: Store) {
        save(text: prismaLines(store).joined(separator: "\n"), suggested: "PRISMA-flow.txt", store: store)
    }

    /// A vector diagram, so it stays crisp when it goes into a thesis at any size.
    static func exportPrismaSVG(_ store: Store) {
        save(text: prismaSVG(store), suggested: "PRISMA-flow.svg", store: store)
    }

    static func prismaSVG(_ store: Store) -> String {
        let p = store.prisma
        let w = 720.0
        var y = 40.0
        let variant = store.prismaVariant
        _ = variant
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(w))" height="880" viewBox="0 0 \(Int(w)) 880" font-family="Helvetica, Arial, sans-serif">
        <rect width="100%" height="100%" fill="white"/>
        <defs><marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">
        <path d="M0,0 L8,4 L0,8 z" fill="#9CA3AF"/></marker></defs>
        """

        func box(_ x: Double, _ y: Double, _ title: String, _ n: Int, _ detail: [String],
                 highlight: Bool = false) -> String {
            let h = 56.0 + Double(detail.count) * 12
            var s = """
            <rect x="\(x)" y="\(y)" width="280" height="\(h)" fill="\(highlight ? "#DCFCE7" : "white")" \
            stroke="\(highlight ? "#16A34A" : "#9CA3AF")" stroke-width="\(highlight ? 1.5 : 1)"/>
            <text x="\(x + 12)" y="\(y + 20)" font-size="11.5" fill="#111827">\(escape(title))</text>
            <text x="\(x + 12)" y="\(y + 38)" font-size="13" font-weight="600" fill="#374151">(n = \(n))</text>
            """
            for (i, d) in detail.enumerated() {
                s += "<text x=\"\(x + 12)\" y=\"\(y + 54 + Double(i) * 12)\" font-size="
                s += "\"9.5\" fill=\"#6B7280\">\(escape(d))</text>"
            }
            return s
        }
        func phase(_ y: Double, _ t: String) -> String {
            "<text x=\"20\" y=\"\(y)\" font-size=\"10\" font-weight=\"700\" letter-spacing=\"1.2\" fill=\"#6B7280\">\(t.uppercased())</text>"
        }
        func vArrow(_ x: Double, _ y1: Double, _ y2: Double) -> String {
            "<line x1=\"\(x)\" y1=\"\(y1)\" x2=\"\(x)\" y2=\"\(y2)\" stroke=\"#9CA3AF\" marker-end=\"url(#a)\"/>"
        }
        func hArrow(_ x1: Double, _ x2: Double, _ y: Double) -> String {
            "<line x1=\"\(x1)\" y1=\"\(y)\" x2=\"\(x2)\" y2=\"\(y)\" stroke=\"#9CA3AF\" marker-end=\"url(#a)\"/>"
        }

        let leftX = 20.0, rightX = 400.0
        svg += phase(y, "Identification"); y += 14
        let idDetail = ["Databases (n = \(p.fromDatabases))", "Registers (n = \(p.fromRegisters))"]
        svg += box(leftX, y, "Records identified from:", p.identified, idDetail)
        svg += box(rightX, y, "Records removed before screening:", p.removedBeforeScreening,
                   ["Duplicate records removed (n = \(p.duplicates))",
                    "Marked ineligible by automation (n = \(p.automationRemoved))",
                    "Removed for other reasons (n = \(p.otherRemoved))"])
        svg += hArrow(leftX + 280, rightX, y + 30)
        let idH = 56 + Double(idDetail.count) * 12
        y += idH
        svg += vArrow(leftX + 140, y, y + 30); y += 36

        svg += phase(y, "Screening"); y += 14
        svg += box(leftX, y, "Records screened", p.screened, [])
        svg += box(rightX, y, "Records excluded", p.excludedScreening, [])
        svg += hArrow(leftX + 280, rightX, y + 30)
        y += 56; svg += vArrow(leftX + 140, y, y + 30); y += 36

        svg += box(leftX, y, "Reports sought for retrieval", p.sought, [])
        svg += box(rightX, y, "Reports not retrieved", p.notRetrieved, [])
        svg += hArrow(leftX + 280, rightX, y + 30)
        y += 56; svg += vArrow(leftX + 140, y, y + 30); y += 36

        let exDetail = p.exclusionReasons.map { "\($0.0): \($0.1)" }
        svg += box(leftX, y, "Reports assessed for eligibility", p.assessed, [])
        svg += box(rightX, y, "Reports excluded", p.excludedEligibility, exDetail)
        svg += hArrow(leftX + 280, rightX, y + 30)
        y += max(56, 56 + Double(exDetail.count) * 12)
        svg += vArrow(leftX + 140, y, y + 30); y += 36

        svg += phase(y, "Included"); y += 14
        svg += box(leftX, y, "Studies included in review", p.includedStudies,
                   ["Reports of included studies (n = \(p.includedReports))"], highlight: true)
        svg += "</svg>"
        return svg
    }

    // MARK: AI use

    /// The declaration journals now ask for, written from the trail rather than from memory.
    ///
    /// Elsevier, Springer Nature, JAMA, Nature and the ICMJE all require authors to state how
    /// generative AI was used and to confirm they take responsibility for the content. Most
    /// people write that paragraph from memory at submission. This writes it from a record
    /// made at the time, and — the part that matters — it will say so plainly when suggestions
    /// were never checked.
    static func aiDisclosureText(_ store: Store) -> String {
        let s = store.aiSummary
        var out = "# Declaration of generative AI use\n\n"
        out += "**Review:** \(store.project?.name ?? "Untitled")\n"
        if let q = store.project?.question, !q.isEmpty { out += "**Question:** \(q)\n" }
        out += "**Prepared:** \(Date().formatted(date: .long, time: .shortened))\n\n"

        guard s.everUsed else {
            out += "## Statement\n\n"
            out += "No generative AI was used at any stage of this review. Sieve records every "
            out += "assistant interaction, and none took place in this project.\n"
            return out
        }

        out += "## Statement\n\n"
        out += "Generative AI was used during the preparation of this review. "
        out += "The tool\(s.models.count == 1 ? " was" : "s were") \(s.models.joined(separator: ", ")), "
        out += "accessed through Sieve between "
        out += "\(s.firstUse?.formatted(date: .long, time: .omitted) ?? "-") and "
        out += "\(s.lastUse?.formatted(date: .long, time: .omitted) ?? "-"). "
        out += "AI was used only to *suggest*; it made no screening decision and wrote no text "
        out += "into the review that was not reviewed by the author. "
        if s.pending == 0 {
            out += "**Every AI suggestion was subsequently checked by the author against the "
            out += "source and accepted, edited or rejected.** "
        } else {
            out += "**\(s.pending) of \(s.total) AI outputs had not been checked by the author "
            out += "at the time of writing"
            if s.unverifiedInIncluded > 0 {
                out += ", including \(s.unverifiedInIncluded) relating to studies included in the review"
            }
            out += ".** "
        }
        out += "The author takes full responsibility for the content of this review.\n\n"

        out += "## What it was used for\n\n"
        out += "| Task | Times | What it was allowed to do |\n|---|---|---|\n"
        for (kind, n) in s.byKind {
            let scope: String
            switch kind {
            case .screen: scope = "Suggest include or exclude. Recorded only; every decision was made by the author."
            case .suggestTag: scope = "Propose a category for a passage the author had already highlighted."
            case .draftCell: scope = "Draft a data-extraction cell from the author's own highlights of that paper."
            case .askCorpus: scope = "Answer a question using only the author's highlights. Shapes no stored data."
            case .buildQueries: scope = "Propose alternative database search strings."
            }
            out += "| \(kind.label) | \(n) | \(scope) |\n"
        }

        out += "\n## What the author did about it\n\n"
        out += "| Outcome | Count |\n|---|---|\n"
        for (outcome, n) in s.byOutcome { out += "| \(outcome.label) | \(n) |\n" }

        let adjudicable = store.aiEvents.filter { $0.kind.needsAdjudication }
        let checked = adjudicable.filter { $0.outcome != .pending }.count
        if !adjudicable.isEmpty {
            let pct = Int(round(Double(checked) / Double(adjudicable.count) * 100))
            out += "\n\(checked) of \(adjudicable.count) suggestions requiring a judgement were "
            out += "adjudicated (\(pct)%).\n"
        }

        out += "\n## What AI was not used for\n\n"
        out += "- No screening or eligibility decision was taken by AI. Every stage change in the "
        out += "PRISMA flow was made by the author.\n"
        out += "- No text was extracted from a source by AI. Every highlight was made by the author "
        out += "selecting it in the PDF.\n"
        out += "- Abstracts, keywords and conclusions read out of PDFs were extracted by text parsing, "
        out += "not by a model.\n"
        out += "- No AI was used to write the review itself.\n"

        out += "\n## Full record\n\n"
        out += "Every interaction below was logged when it happened, not reconstructed afterwards.\n\n"
        for e in store.aiEvents.sorted(by: { $0.at < $1.at }) {
            out += "- \(e.line(store: store))\n"
        }
        return out
    }

    static func exportAIDisclosure(_ store: Store) {
        save(text: aiDisclosureText(store), suggested: "AI-use-declaration.md", store: store)
    }

    static func aiTrailCSV(_ store: Store) -> String {
        var out = ["When,Task,Model,Subject,Column,Asked,It said,Confidence,Outcome,Decided,Note"]
        for e in store.aiEvents.sorted(by: { $0.at < $1.at }) {
            let subject: String
            switch e.subjectKind {
            case "paper", "cell": subject = store.paper(e.subjectId)?.citeKey ?? ""
            case "evidence": subject = store.evidence(e.subjectId)?.quote ?? ""
            default: subject = store.project?.name ?? ""
            }
            out.append([
                e.at.formatted(date: .numeric, time: .standard),
                e.kind.label, e.model, subject,
                store.columns.first { $0.id == e.columnId }?.name ?? "",
                e.asked, e.said, e.confidence, e.outcome.label,
                e.outcomeAt?.formatted(date: .numeric, time: .standard) ?? "",
                e.humanNote
            ].map(csvEscape).joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    static func exportAITrail(_ store: Store) {
        save(text: aiTrailCSV(store), suggested: "AI-trail.csv", store: store)
    }

    // MARK: Spreadsheet and PDF

    static func exportMatrixXLSX(_ store: Store, rows: [Paper]) {
        let data = XLSX.build(grid: matrixGrid(store, rows: rows),
                              sheetName: store.project?.name ?? "Matrix")
        save(data: data, suggested: "review-matrix.xlsx", store: store)
    }

    static func exportMatrixPDF(_ store: Store, rows: [Paper]) {
        let subtitle = [store.project?.question, "\(rows.count) papers",
                        Date().formatted(date: .long, time: .omitted)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        let data = PDFReport.table(matrixGrid(store, rows: rows),
                                   title: store.project?.name ?? "Literature review matrix",
                                   subtitle: subtitle)
        save(data: data, suggested: "review-matrix.pdf", store: store)
    }

    /// One PDF holding the whole review: question, criteria, PRISMA counts, the matrix
    /// contents, every highlight grouped by category, and the reference list.
    static func reportBlocks(_ store: Store) -> [PDFReport.Block] {
        var b: [PDFReport.Block] = []
        let proj = store.project
        b.append(.init(kind: .title, text: proj?.name ?? "Literature review"))
        b.append(.init(kind: .caption, text: "Generated by Sieve · \(Date().formatted(date: .long, time: .shortened))"))
        if let q = proj?.question, !q.isEmpty {
            b.append(.init(kind: .heading, text: "Review question"))
            b.append(.init(kind: .body, text: q))
        }
        if let inc = proj?.inclusionCriteria, !inc.isEmpty {
            b.append(.init(kind: .heading, text: "Inclusion criteria"))
            b.append(.init(kind: .body, text: inc))
        }
        if let exc = proj?.exclusionCriteria, !exc.isEmpty {
            b.append(.init(kind: .heading, text: "Exclusion criteria"))
            b.append(.init(kind: .body, text: exc))
        }
        b.append(.init(kind: .rule))

        b.append(.init(kind: .heading, text: "PRISMA 2020 flow"))
        for line in prismaLines(store).dropFirst(3) where !line.isEmpty {
            b.append(.init(kind: line.hasPrefix("  ") ? .body : .subheading,
                           text: line.trimmingCharacters(in: .whitespaces)))
        }

        b.append(.init(kind: .pageBreak))
        b.append(.init(kind: .heading, text: "Included papers"))
        for p in store.included {
            b.append(.init(kind: .subheading, text: p.reference))
            for c in store.columns {
                let cell = store.cell(p.id, c.id)
                guard !cell.value.isEmpty else { continue }
                b.append(.init(kind: .body, text: "\(c.name): \(cell.value)"))
            }
            if !p.conclusion.isEmpty { b.append(.init(kind: .body, text: "Conclusion: \(p.conclusion)")) }
            let ev = store.evidence(forPaper: p.id)
            if !ev.isEmpty { b.append(.init(kind: .caption, text: "\(ev.count) highlights recorded")) }
            b.append(.init(kind: .rule))
        }

        b.append(.init(kind: .pageBreak))
        b.append(.init(kind: .heading, text: "Evidence, by category"))
        for tag in store.tags {
            let items = store.evidence.filter { $0.tagIds.contains(tag.id) }
            guard !items.isEmpty else { continue }
            b.append(.init(kind: .subheading, text: "\(tag.name)  (\(items.count))"))
            if !tag.detail.isEmpty { b.append(.init(kind: .caption, text: tag.detail)) }
            for e in items {
                guard let p = store.paper(e.paperId) else { continue }
                b.append(.init(kind: .quote, text: "\u{201C}\(e.quote)\u{201D}"))
                b.append(.init(kind: .caption,
                               text: "\(p.authorLine), \(p.year.map(String.init) ?? "n.d."), p.\(e.page + 1)"
                                   + (p.doi.isEmpty ? "" : " · doi.org/\(p.doi)")
                                   + (e.note.isEmpty ? "" : "  —  note: \(e.note)")))
            }
        }

        b.append(.init(kind: .pageBreak))
        b.append(.init(kind: .heading, text: "References"))
        for p in store.included { b.append(.init(kind: .body, text: p.reference)) }
        return b
    }

    static func exportReportPDF(_ store: Store) {
        save(data: PDFReport.build(reportBlocks(store)), suggested: "review-report.pdf", store: store)
    }

    // MARK: Everything, in one folder

    /// Writes every export Sieve can produce into one dated folder, wherever you choose —
    /// so handing the whole review to a supervisor is a single action.
    static func exportEverything(_ store: Store) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Choose where to put the export folder"
        panel.directoryURL = Library.exportDir
        guard panel.runModal() == .OK, let base = panel.url else { return }

        let stamp = Date().formatted(.iso8601.year().month().day())
        let name = ((store.project?.name ?? "Review")
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")) + "-" + stamp
        var dir = base.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: dir.path) {
            dir = base.appendingPathComponent("\(name)-\(n)", isDirectory: true); n += 1
        }

        let included = store.included
        let all = store.papers
        var written: [String] = []

        func write(_ filename: String, _ data: Data) {
            do {
                try data.write(to: dir.appendingPathComponent(filename))
                written.append(filename)
            } catch { store.flash("Could not write \(filename)") }
        }
        func write(_ filename: String, _ text: String) { write(filename, Data(text.utf8)) }

        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { store.flash("Could not create the export folder"); return }

        write("01-review-report.pdf", PDFReport.build(reportBlocks(store)))
        write("02-matrix.xlsx", XLSX.build(grid: matrixGrid(store, rows: included),
                                           sheetName: store.project?.name ?? "Matrix"))
        write("02-matrix.pdf", PDFReport.table(matrixGrid(store, rows: included),
                                               title: store.project?.name ?? "Matrix",
                                               subtitle: "\(included.count) included papers"))
        write("02-matrix.csv", csvText(matrixGrid(store, rows: included)))
        write("03-PRISMA-flow.txt", prismaLines(store).joined(separator: "\n"))
        write("03-PRISMA-flow.svg", prismaSVG(store))
        write("03-PRISMA-2020-checklist.csv", checklistCSV(store))
        write("04-highlights.md", evidenceMarkdown(store, store.evidence))
        write("04-highlights.csv", evidenceCSV(store, store.evidence))
        write("04-highlights.xlsx", XLSX.build(grid: evidenceGrid(store, store.evidence),
                                               sheetName: "Highlights"))
        write("05-included.bib", bibText(store, included))
        write("05-included.ris", risText(store, included))
        write("05-everything.ris", risText(store, all))
        write("06-library.csv", papersCSV(store, all))
        write("06-AI-use-declaration.md", aiDisclosureText(store))
        write("06-AI-trail.csv", aiTrailCSV(store))
        write("07-search-history.txt", store.searchRuns().map {
            "\"\($0.query)\"\n  \($0.providers)\n  \($0.results) results, \($0.imported) added — \($0.at.formatted(date: .long, time: .shortened))"
        }.joined(separator: "\n\n"))
        write("README.txt", """
        \(store.project?.name ?? "Review")
        Exported from Sieve on \(Date().formatted(date: .long, time: .shortened))

        \(store.project?.question ?? "")

        01  The whole review as one PDF — question, criteria, PRISMA, matrix, every highlight, references.
        02  The literature review matrix, as a spreadsheet, a PDF table and a CSV.
        03  The PRISMA 2020 flow: counts as text, a vector diagram for the thesis, and the
            27-item reporting checklist with where each item is reported.
        04  Every highlight with its page, category, source paper and DOI.
        05  BibTeX and RIS for the included papers, and RIS for everything. Import straight
            into Zotero, Mendeley, EndNote, Word or LaTeX — your notes and highlights travel
            with the records.
        06  The full library including everything screened out, with the reason, plus the
            declaration of generative AI use that journals now ask for, and the complete
            record it was written from.
        07  Every database search that was run, with dates — required when reporting a systematic review.

        Papers: \(all.count) total, \(included.count) included.
        Highlights: \(store.evidence.count).
        """)

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
        store.flash("Exported \(written.count) files to \(dir.lastPathComponent)")
    }

    // MARK: Text builders reused by both single exports and the bundle

    static func csvText(_ grid: [[String]]) -> String {
        grid.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n")
    }

    static func evidenceGrid(_ store: Store, _ items: [Evidence]) -> [[String]] {
        var grid: [[String]] = [["Quote", "My note", "Categories", "Page", "Paper", "Authors",
                                 "Year", "DOI", "Source database", "Source link", "Date highlighted", "AI"]]
        for e in items {
            let p = store.paper(e.paperId)
            var link = ""
            if let p { link = p.doi.isEmpty ? p.url : "https://doi.org/\(p.doi)" }
            grid.append([
                e.quote, e.note,
                e.tagIds.compactMap { store.tag($0)?.name }.joined(separator: "; "),
                e.page >= 0 ? String(e.page + 1) : "",
                p?.title ?? "", p?.authors.joined(separator: "; ") ?? "",
                p?.year.map(String.init) ?? "", p?.doi ?? "", p?.sourceDB ?? "", link,
                e.createdAt.formatted(date: .numeric, time: .omitted),
                e.aiGenerated ? "yes" : "no"
            ])
        }
        return grid
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
