import Foundation
import PDFKit
import AppKit

/// Everything that turns an outside file into a record in the review.
enum Importers {

    // MARK: - Dropped / chosen PDFs

    struct PDFMetadata {
        var title = ""
        var authors: [String] = []
        var year: Int?
        var doi = ""
        var venue = ""
        var abstract = ""
        var url = ""
        var pubDate = ""
        var citedBy = 0
        var openAlexId = ""
        var sdgs: [String] = []
        var references: [String] = []
    }

    /// Reads what the PDF itself knows, then falls back to scraping the first page —
    /// a DOI printed in the header is usually the most reliable identifier a paper has.
    static func metadata(of url: URL) -> PDFMetadata {
        var m = PDFMetadata()
        guard let doc = PDFDocument(url: url) else {
            m.title = url.deletingPathExtension().lastPathComponent
            return m
        }
        if let attrs = doc.documentAttributes {
            m.title = (attrs[PDFDocumentAttribute.titleAttribute] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let author = attrs[PDFDocumentAttribute.authorAttribute] as? String ?? ""
            if !author.isEmpty {
                m.authors = author.split(whereSeparator: { ",;&".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            if let date = attrs[PDFDocumentAttribute.creationDateAttribute] as? Date {
                m.year = Calendar.current.component(.year, from: date)
            }
        }
        let firstPage = doc.page(at: 0)?.string ?? ""
        if let doi = extractDOI(from: firstPage) { m.doi = doi }
        if m.title.isEmpty || m.title.count < 6 || m.title.lowercased().hasSuffix(".dvi") {
            m.title = guessTitle(from: firstPage)
                ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        }
        if m.year == nil, let y = firstPage.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
            m.year = Int(firstPage[y])
        }
        return m
    }

    static func extractDOI(from text: String) -> String? {
        let pattern = "10\\.\\d{4,9}/[-._;()/:A-Za-z0-9]+"
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        var doi = String(text[r]).lowercased()
        while let last = doi.last, ".,;)".contains(last) { doi.removeLast() }
        return doi
    }

    /// The title of an academic PDF is almost always the largest run of text near the top
    /// of page one. Without font metrics, the best cheap heuristic is the first substantial
    /// line that isn't a journal masthead or a page number.
    static func guessTitle(from page: String) -> String? {
        let lines = page.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines.prefix(12) {
            let words = line.split(separator: " ").count
            let looksLikeHeader = line.lowercased().contains("downloaded from")
                || line.lowercased().hasPrefix("vol")
                || line.lowercased().hasPrefix("doi")
                || line.range(of: "^\\d+$", options: .regularExpression) != nil
                || line.range(of: "[A-Za-z0-9._%+-]+@", options: .regularExpression) != nil
            if words >= 4, line.count >= 20, line.count < 250, !looksLikeHeader {
                return line
            }
        }
        return lines.first
    }

    /// Copies the file into the library so the review folder stays self-contained, then
    /// creates (or enriches) the matching record.
    ///
    /// A PDF's own metadata is usually junk — LaTeX leaves the title as "paper.dvi" and the
    /// abstract nowhere at all. So the DOI printed on page one is used to pull the real
    /// record from OpenAlex (abstract, SDGs, references) and Crossref (authoritative
    /// bibliographic fields); failing that, the guessed title is searched against OpenAlex.
    @MainActor
    static func importPDF(at url: URL, store: Store, enrich: Bool = true) async -> Int? {
        let local = metadata(of: url)
        var meta = local

        // Read the paper's own abstract, keywords and conclusion straight out of the text
        // layer. This needs no network and no model, so it works on a paywalled PDF that no
        // database will tell us anything about.
        let sections = PaperText.sections(of: url)

        if enrich {
            if let online = await lookupOnline(doi: local.doi, title: local.title, year: local.year) {
                meta.title = online.title.isEmpty ? meta.title : online.title
                meta.authors = online.authors.isEmpty ? meta.authors : online.authors
                meta.year = online.year ?? meta.year
                meta.venue = online.venue.isEmpty ? meta.venue : online.venue
                meta.doi = online.doi.isEmpty ? meta.doi : online.doi
                meta.abstract = online.abstract
                meta.url = online.url
                meta.sdgs = online.sdgs
                meta.pubDate = online.pubDate
                meta.openAlexId = online.openAlexId
                meta.references = online.references
                meta.citedBy = online.citedBy
            }
        }

        // The PDF's own abstract wins when the databases have none — which is most of the
        // time for Crossref and PubMed records.
        if meta.abstract.isEmpty { meta.abstract = sections.abstract }

        // Everything below happens BEFORE anything is written to disk. The old order — copy
        // first, then look for an existing record — is what produced 126 duplicate files in
        // a real library: every re-drop wrote another `-N` copy and orphaned the last one.
        let key = Dedupe.key(doi: meta.doi, title: meta.title, year: meta.year)
        let fingerprint = Library.fingerprint(of: url)

        // The same bytes already in the library, under any record.
        if let hash = fingerprint,
           let twin = store.papers.first(where: { $0.fileHash == hash && $0.hasPDF }) {
            store.flash("Already in this review as “\(twin.title.prefix(40))…” — nothing copied")
            return twin.id
        }

        if let existing = store.papers.first(where: { $0.dedupeKey == key }) {
            // The record is here already. Only bring in the file if it has none, and top up
            // whatever fields were thin.
            var q = existing
            if !existing.hasPDF {
                guard let placed = copyIntoLibrary(url, title: meta.title, store: store) else { return nil }
                q.pdfPath = placed.path
                q.accessedAt = Date()
                q.fileHash = fingerprint ?? ""
            }
            if q.abstract.isEmpty { q.abstract = meta.abstract }
            if q.venue.isEmpty { q.venue = meta.venue }
            if q.doi.isEmpty { q.doi = meta.doi }
            if q.authors.isEmpty { q.authors = meta.authors }
            if q.year == nil { q.year = meta.year }
            if q.sdgs.isEmpty { q.sdgs = meta.sdgs }
            if q.references.isEmpty { q.references = meta.references }
            if q.openAlexId.isEmpty { q.openAlexId = meta.openAlexId }
            if q.keywords.isEmpty { q.keywords = sections.keywords }
            if q.extractedConclusion.isEmpty {
                q.extractedConclusion = sections.conclusion
                q.conclusionHeading = sections.conclusionHeading
            }
            store.updatePaper(q, recordUndo: false)
            store.flash(existing.hasPDF
                        ? "Already in this review — details topped up, no copy made"
                        : "Attached the PDF to “\(q.title.prefix(36))…” already in this review")
            return q.id
        }

        guard let dest = copyIntoLibrary(url, title: meta.title, store: store) else { return nil }

        guard let id = store.addManualPaper(title: meta.title, authors: meta.authors, year: meta.year,
                                            venue: meta.venue, doi: meta.doi, pdfPath: dest.path,
                                            sourceDB: "Dropped PDF", abstract: meta.abstract,
                                            url: meta.url) else {
            try? FileManager.default.removeItem(at: dest)   // no record kept it; do not leave the file
            return nil
        }
        if var p = store.paper(id) {
            p.sdgs = meta.sdgs
            p.pubDate = meta.pubDate
            p.openAlexId = meta.openAlexId
            p.references = meta.references
            p.citedBy = meta.citedBy
            p.keywords = sections.keywords
            p.extractedConclusion = sections.conclusion
            p.conclusionHeading = sections.conclusionHeading
            p.fileHash = fingerprint ?? ""
            store.updatePaper(p, recordUndo: false)
        }
        return id
    }

    /// Copies a PDF into the folder belonging to the review that is open. Each review owns
    /// its own directory, so one review's papers are never mixed with another's.
    @MainActor
    private static func copyIntoLibrary(_ url: URL, title: String, store: Store) -> URL? {
        guard let project = store.project else { return nil }
        let dir = Library.pdfDir(id: project.id, name: project.name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stem = (title.isEmpty ? url.deletingPathExtension().lastPathComponent : title)
            .prefix(60)
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " +", with: "_", options: .regularExpression)
        let base = stem.isEmpty ? "paper" : stem

        var dest = dir.appendingPathComponent("\(base).pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base)-\(n).pdf"); n += 1
        }
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            store.flash("Could not copy the PDF: \(error.localizedDescription)")
            return nil
        }
    }

    /// Looks the paper up online. DOI is tried first because it is exact; a title search is
    /// the fallback, and is only accepted when the returned title really is the same paper.
    static func lookupOnline(doi: String, title: String, year: Int?) async -> PDFMetadata? {
        if !doi.isEmpty {
            if let m = await lookupOpenAlex(path: "works/doi:\(doi)") { return m }
            if let m = await lookupDOI(doi) { return m }
        }
        guard title.count > 12 else { return nil }
        let q = Net.enc(title.prefix(180).description)
        guard let url = URL(string: "https://api.openalex.org/works?search=\(q)&per-page=1"),
              let root = try? await Net.json(url) as? [String: Any],
              let first = (root["results"] as? [Any])?.first as? [String: Any],
              let found = first["display_name"] as? String,
              similar(found, title) else { return nil }
        return parseOpenAlex(first)
    }

    private static func lookupOpenAlex(path: String) async -> PDFMetadata? {
        guard let url = URL(string: "https://api.openalex.org/\(path)"),
              let root = try? await Net.json(url) as? [String: Any],
              root["display_name"] != nil else { return nil }
        return parseOpenAlex(root)
    }

    private static func parseOpenAlex(_ w: [String: Any]) -> PDFMetadata {
        var m = PDFMetadata()
        m.title = (w["display_name"] as? String) ?? ""
        m.authors = (w["authorships"] as? [Any] ?? []).compactMap { a in
            ((a as? [String: Any])?["author"] as? [String: Any])?["display_name"] as? String
        }
        m.year = w["publication_year"] as? Int
        let loc = (w["best_oa_location"] ?? w["primary_location"]) as? [String: Any] ?? [:]
        m.venue = ((loc["source"] as? [String: Any])?["display_name"] as? String) ?? ""
        m.doi = ((w["doi"] as? String) ?? "")
            .replacingOccurrences(of: "https://doi.org/", with: "").lowercased()
        m.abstract = OpenAlexProvider.invertedAbstract(w["abstract_inverted_index"])
        m.url = m.doi.isEmpty ? ((loc["landing_page_url"] as? String) ?? "") : "https://doi.org/\(m.doi)"
        m.pubDate = (w["publication_date"] as? String) ?? ""
        m.citedBy = (w["cited_by_count"] as? Int) ?? 0
        m.openAlexId = ((w["id"] as? String) ?? "")
            .replacingOccurrences(of: "https://openalex.org/", with: "")
        m.sdgs = (w["sustainable_development_goals"] as? [Any] ?? []).compactMap { g in
            guard let d = g as? [String: Any], ((d["score"] as? Double) ?? 0) >= 0.4 else { return nil }
            return d["display_name"] as? String
        }
        m.references = (w["referenced_works"] as? [Any] ?? []).compactMap {
            ($0 as? String)?.replacingOccurrences(of: "https://openalex.org/", with: "")
        }
        return m
    }

    /// Titles from a PDF are noisy — hyphenation, line breaks, dropped subtitles — so the
    /// match is on normalised words rather than an exact string.
    static func similar(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 })
        }
        let x = norm(a), y = norm(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return Double(x.intersection(y).count) / Double(min(x.count, y.count)) >= 0.6
    }

    /// Crossref by DOI — the authoritative bibliographic record, used when OpenAlex
    /// doesn't have the work.
    static func lookupDOI(_ doi: String) async -> PDFMetadata? {
        guard let url = URL(string: "https://api.crossref.org/works/\(doi)"),
              let root = try? await Net.json(url) as? [String: Any],
              let msg = root["message"] as? [String: Any] else { return nil }
        var m = PDFMetadata()
        m.title = ((msg["title"] as? [Any])?.first as? String) ?? ""
        m.authors = (msg["author"] as? [Any] ?? []).compactMap { a in
            guard let d = a as? [String: Any] else { return nil }
            return [(d["given"] as? String ?? ""), (d["family"] as? String ?? "")]
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let parts = (msg["issued"] as? [String: Any])?["date-parts"] as? [Any],
           let first = parts.first as? [Any], let y = first.first as? Int { m.year = y }
        m.venue = ((msg["container-title"] as? [Any])?.first as? String) ?? ""
        m.abstract = ((msg["abstract"] as? String) ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        m.citedBy = (msg["is-referenced-by-count"] as? Int) ?? 0
        m.url = (msg["URL"] as? String) ?? "https://doi.org/\(doi)"
        m.doi = doi
        return m
    }

    // MARK: - BibTeX

    /// Parses a .bib file well enough for real exports from Zotero, Mendeley and Google Scholar.
    static func parseBibTeX(_ text: String) -> [SearchHit] {
        var hits: [SearchHit] = []
        // Split on @type{ at line starts.
        let entries = text.components(separatedBy: "\n@").enumerated().map { i, s in i == 0 ? s : "@" + s }
        for raw in entries {
            guard let braceIdx = raw.firstIndex(of: "{") else { continue }
            guard raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") else { continue }
            let body = String(raw[raw.index(after: braceIdx)...])
            var fields: [String: String] = [:]
            var key = "", value = ""
            var depth = 0, readingKey = true, inQuote = false
            var chars = Array(body)
            // skip the cite key
            if let comma = chars.firstIndex(of: ",") { chars = Array(chars[(comma + 1)...]) }
            for ch in chars {
                if readingKey {
                    if ch == "=" { readingKey = false; value = "" }
                    else if ch == "," && depth == 0 { key = "" }
                    else { key.append(ch) }
                } else {
                    if ch == "{" { depth += 1; if depth == 1 { continue } }
                    if ch == "}" { depth -= 1; if depth == 0 { continue }; if depth < 0 { break } }
                    if ch == "\"" && depth == 0 { inQuote.toggle(); continue }
                    if ch == "," && depth == 0 && !inQuote {
                        fields[key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                            value.trimmingCharacters(in: .whitespacesAndNewlines)
                        key = ""; value = ""; readingKey = true
                        continue
                    }
                    value.append(ch)
                }
            }
            if !key.isEmpty, !value.isEmpty {
                fields[key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                    value.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "{}\", \n"))
            }
            let title = clean(fields["title"] ?? "")
            guard !title.isEmpty else { continue }
            let authors = (fields["author"] ?? "").components(separatedBy: " and ")
                .map { a -> String in
                    let t = clean(a)
                    if t.contains(",") {
                        let p = t.components(separatedBy: ",")
                        return (p.count > 1 ? p[1].trimmingCharacters(in: .whitespaces) + " " : "") + p[0].trimmingCharacters(in: .whitespaces)
                    }
                    return t
                }.filter { !$0.isEmpty }
            hits.append(SearchHit(
                id: "bib:" + title.prefix(40),
                title: title,
                authors: authors,
                year: Int(clean(fields["year"] ?? "").prefix(4)),
                venue: clean(fields["journal"] ?? fields["booktitle"] ?? fields["publisher"] ?? ""),
                doi: clean(fields["doi"] ?? "").lowercased(),
                abstract: clean(fields["abstract"] ?? ""),
                url: clean(fields["url"] ?? ""),
                pdfURL: "",
                provider: "BibTeX import",
                oaStatus: "",
                citedBy: 0))
        }
        return hits
    }

    // MARK: - RIS

    static func parseRIS(_ text: String) -> [SearchHit] {
        var hits: [SearchHit] = []
        var cur: [String: [String]] = [:]

        func flush() {
            let title = (cur["TI"]?.first ?? cur["T1"]?.first ?? cur["BT"]?.first ?? "")
            guard !title.isEmpty else { cur = [:]; return }
            let authors = ((cur["AU"] ?? []) + (cur["A1"] ?? [])).map { a -> String in
                if a.contains(",") {
                    let p = a.components(separatedBy: ",")
                    return (p.count > 1 ? p[1].trimmingCharacters(in: .whitespaces) + " " : "") + p[0].trimmingCharacters(in: .whitespaces)
                }
                return a
            }
            let yearRaw = cur["PY"]?.first ?? cur["Y1"]?.first ?? cur["DA"]?.first ?? ""
            hits.append(SearchHit(
                id: "ris:" + title.prefix(40),
                title: title,
                authors: authors,
                year: Int(yearRaw.prefix(4)),
                venue: cur["JO"]?.first ?? cur["JF"]?.first ?? cur["T2"]?.first ?? cur["PB"]?.first ?? "",
                doi: (cur["DO"]?.first ?? "").lowercased(),
                abstract: cur["AB"]?.first ?? cur["N2"]?.first ?? "",
                url: cur["UR"]?.first ?? "",
                pdfURL: cur["L1"]?.first ?? "",
                provider: "RIS import",
                oaStatus: "",
                citedBy: 0))
            cur = [:]
        }

        var lastTag = ""
        for line in text.components(separatedBy: .newlines) {
            // A RIS tag line is exactly "XX  - value"; the end marker "ER  -" carries no value.
            if line.count >= 5, line.range(of: "^[A-Z][A-Z0-9]  -", options: .regularExpression) != nil {
                let tag = String(line.prefix(2))
                let value = line.count > 6
                    ? String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) : ""
                if tag == "ER" { flush(); lastTag = ""; continue }
                if tag == "TY" { flush() }
                cur[tag, default: []].append(value)
                lastTag = tag
            } else if !lastTag.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                // continuation of a wrapped field (abstracts wrap constantly)
                if var existing = cur[lastTag], !existing.isEmpty {
                    existing[existing.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
                    cur[lastTag] = existing
                }
            }
        }
        flush()
        return hits
    }

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression)
         .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
         .trimmingCharacters(in: CharacterSet(charactersIn: " ,\n\t\""))
    }

    /// Detects the format and returns records ready to add.
    static func parseBibliography(_ text: String) -> [SearchHit] {
        let head = text.prefix(2000)
        if head.contains("TY  -") || head.range(of: "^[A-Z][A-Z0-9]  - ", options: .regularExpression) != nil {
            return parseRIS(text)
        }
        return parseBibTeX(text)
    }
}
