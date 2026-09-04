import Foundation
import SwiftUI

/// Tops up records that are missing fields — abstracts, SDGs, reference lists, dates.
/// Papers added before a field existed, or imported from a database that doesn't supply it
/// (Crossref rarely has abstracts, PubMed's summary endpoint has none at all), stay thin
/// until this runs. It only ever fills gaps: nothing you typed is overwritten.
@MainActor
final class Enricher: ObservableObject {
    @Published var running = false
    @Published var progress = ""
    @Published var cancelled = false

    struct Result {
        var checked = 0, abstracts = 0, sdgs = 0, references = 0, dates = 0, unmatched = 0
        var keywords = 0, conclusions = 0, noTextLayer = 0
    }

    func enrich(_ papers: [Paper], store: Store) async -> Result {
        running = true
        cancelled = false
        defer { running = false; progress = "" }

        var r = Result()
        for (i, p) in papers.enumerated() {
            if cancelled { break }
            progress = "\(i + 1) / \(papers.count)"
            r.checked += 1
            var q = p

            // Read the PDF first: its own abstract and conclusion are the paper's words, and
            // no database will hand you a conclusion section at all.
            if p.hasPDF, q.keywords.isEmpty || q.extractedConclusion.isEmpty || q.abstract.isEmpty {
                let s = PaperText.sections(of: URL(fileURLWithPath: p.pdfPath))
                if !s.hasTextLayer {
                    r.noTextLayer += 1
                } else {
                    if q.keywords.isEmpty, !s.keywords.isEmpty { q.keywords = s.keywords; r.keywords += 1 }
                    if q.extractedConclusion.isEmpty, !s.conclusion.isEmpty {
                        q.extractedConclusion = s.conclusion
                        q.conclusionHeading = s.conclusionHeading
                        r.conclusions += 1
                    }
                    if q.abstract.isEmpty, !s.abstract.isEmpty { q.abstract = s.abstract; r.abstracts += 1 }
                }
            }

            guard let m = await Importers.lookupOnline(doi: q.doi, title: q.title, year: q.year) else {
                if q != p { store.updatePaper(q) }
                r.unmatched += 1
                continue
            }

            if q.abstract.isEmpty, !m.abstract.isEmpty { q.abstract = m.abstract; r.abstracts += 1 }
            if q.sdgs.isEmpty, !m.sdgs.isEmpty { q.sdgs = m.sdgs; r.sdgs += 1 }
            if q.references.isEmpty, !m.references.isEmpty { q.references = m.references; r.references += 1 }
            if q.pubDate.isEmpty, !m.pubDate.isEmpty { q.pubDate = m.pubDate; r.dates += 1 }
            if q.openAlexId.isEmpty { q.openAlexId = m.openAlexId }
            if q.doi.isEmpty { q.doi = m.doi }
            if q.venue.isEmpty { q.venue = m.venue }
            if q.authors.isEmpty { q.authors = m.authors }
            if q.year == nil { q.year = m.year }
            if q.citedBy == 0 { q.citedBy = m.citedBy }
            if q.url.isEmpty { q.url = m.url }
            store.updatePaper(q)

            // OpenAlex asks for no more than ~10 requests a second; this stays well under.
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return r
    }

    static func summary(_ r: Result) -> String {
        var parts: [String] = []
        if r.abstracts > 0 { parts.append("\(r.abstracts) abstract\(r.abstracts == 1 ? "" : "s")") }
        if r.keywords > 0 { parts.append("\(r.keywords) keyword list\(r.keywords == 1 ? "" : "s")") }
        if r.conclusions > 0 { parts.append("\(r.conclusions) conclusion\(r.conclusions == 1 ? "" : "s")") }
        if r.sdgs > 0 { parts.append("\(r.sdgs) SDG tag\(r.sdgs == 1 ? "" : "s")") }
        if r.references > 0 { parts.append("\(r.references) reference list\(r.references == 1 ? "" : "s")") }
        if r.dates > 0 { parts.append("\(r.dates) publication date\(r.dates == 1 ? "" : "s")") }
        if parts.isEmpty { return "Checked \(r.checked) papers — nothing was missing" }
        return "Filled in " + parts.joined(separator: ", ")
            + (r.unmatched > 0 ? " · \(r.unmatched) not found online" : "")
            + (r.noTextLayer > 0 ? " · \(r.noTextLayer) PDF\(r.noTextLayer == 1 ? " is a scan" : "s are scans") with no text to read" : "")
    }
}
