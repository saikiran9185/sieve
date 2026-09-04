import Foundation
import PDFKit

/// Pulls the parts of a paper a researcher actually reads first — abstract, keywords and
/// conclusion — straight out of the PDF's text layer. No model, no network, no guessing at
/// meaning: it finds the section headings the way a person skimming the page does, and
/// returns the text between them verbatim.
enum PaperText {

    struct Sections {
        var abstract = ""
        var keywords: [String] = []
        var conclusion = ""
        var conclusionHeading = ""     // which heading it was found under, for honesty in the UI
        var fullText = ""
        var pageCount = 0
        var hasTextLayer = true        // false for a scan — nothing can be extracted without OCR

        var isEmpty: Bool { abstract.isEmpty && conclusion.isEmpty && keywords.isEmpty }
        /// True when the conclusion is the closing paragraphs rather than a real section.
        var conclusionIsApproximate: Bool { !conclusion.isEmpty && conclusionHeading.isEmpty }
    }

    // MARK: - Entry point

    static func sections(of url: URL) -> Sections {
        guard let doc = PDFDocument(url: url) else { return Sections() }
        var s = Sections()
        s.pageCount = doc.pageCount

        var pages: [String] = []
        for i in 0..<doc.pageCount { pages.append(doc.page(at: i)?.string ?? "") }
        let full = pages.joined(separator: "\n\n")
        s.fullText = full
        // A scan has a PDF page but no text layer; say so rather than returning empty fields.
        guard full.count > 200 else { s.hasTextLayer = false; return s }

        // The abstract is reliably on the first page or two. The conclusion is not: in a
        // 50-page review it can sit at 50% with thirty pages of references after it, so the
        // whole document is searched and the *last* heading that yields real text wins.
        let front = pages.prefix(3).joined(separator: "\n\n")
        s.abstract = abstract(in: front)
        s.keywords = keywords(in: front)
        let c = conclusion(in: full)
        s.conclusion = c.text
        s.conclusionHeading = c.heading
        return s
    }

    // MARK: - Abstract

    static func abstract(in text: String) -> String {
        let lines = normalisedLines(text)

        // A heading line that is just the word "Abstract", or a paragraph starting "Abstract—".
        guard let start = lines.firstIndex(where: { isAbstractHeading($0) }) else {
            return ""
        }

        var body: [String] = []
        // "Abstract— The paper shows…" keeps its text on the same line.
        let head = lines[start]
        if let r = head.range(of: "^\\s*(abstract|summary)\\s*[:.\\u{2014}\\u{2013}-]+\\s*",
                              options: [.regularExpression, .caseInsensitive]) {
            let rest = String(head[r.upperBound...])
            if rest.count > 30 { body.append(rest) }
        }

        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            if isAbstractTerminator(line) { break }
            if body.joined(separator: " ").count > 4000 { break }
            if !line.isEmpty { body.append(line) }
            i += 1
        }
        return clean(body.joined(separator: " "))
    }

    private static func isAbstractHeading(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces).lowercased()
        if l == "abstract" || l == "abstract:" || l == "a b s t r a c t" || l == "summary" { return true }
        // "Abstract—" / "Abstract:" followed by the text itself.
        return line.range(of: "^\\s*(abstract|summary)\\s*[:.\\u{2014}\\u{2013}-]\\s*\\S",
                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isAbstractTerminator(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces).lowercased()
        if l.isEmpty { return false }
        let stops = ["keywords", "key words", "index terms", "ccs concepts", "introduction",
                     "1 introduction", "1. introduction", "i. introduction", "author keywords",
                     "acm reference format", "categories and subject descriptors"]
        for stop in stops where l.hasPrefix(stop) { return true }
        return line.range(of: "^\\s*(1|I)\\s*[.)]?\\s+introduction\\b",
                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Keywords

    static func keywords(in text: String) -> [String] {
        let lines = normalisedLines(text)
        let labels = "keywords|key words|key-words|index terms|author keywords|ccs concepts"
        for (i, line) in lines.enumerated() {
            guard let r = line.range(of: "^\\s*(\(labels))\\s*[:.\\u{2014}\\u{2013}-]*\\s*",
                                     options: [.regularExpression, .caseInsensitive]) else { continue }
            var payload = String(line[r.upperBound...])
            // A bare "Keywords" heading puts the list on the following line.
            var j = i + 1
            while payload.trimmingCharacters(in: .whitespaces).count < 3, j < lines.count, j < i + 3 {
                payload = lines[j]; j += 1
            }
            // Take one more line if the list clearly continues.
            if j < lines.count, !payload.hasSuffix("."), payload.count < 60,
               !isSectionHeading(lines[j]) {
                payload += ", " + lines[j]
            }
            let parts = payload
                .components(separatedBy: CharacterSet(charactersIn: ",;·•\u{2022}"))
                .map { clean($0).trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
                .filter { $0.count > 1 && $0.count < 60 }
            if !parts.isEmpty { return Array(parts.prefix(15)) }
        }
        return []
    }

    // MARK: - Conclusion

    static func conclusion(in text: String) -> (text: String, heading: String) {
        let lines = normalisedLines(text)

        // Collect every heading that could open a conclusion, then try them newest-first.
        // A candidate that yields only a line or two is usually a table-of-contents entry or
        // a structured-abstract label, so the search continues past it.
        var candidates: [(index: Int, heading: String)] = []
        for (i, line) in lines.enumerated() {
            if let h = conclusionHeading(line) { candidates.append((i, h)) }
        }

        for candidate in candidates.reversed() {
            let body = read(from: candidate.index, in: lines)
            if body.count >= 200 { return (body, candidate.heading) }
        }
        // Nothing substantial under a heading — fall back to the closing paragraphs, and the
        // empty heading tells the UI to label them as such.
        if let best = candidates.reversed().map({ read(from: $0.index, in: lines) })
            .first(where: { $0.count > 60 }) {
            let tail = fallbackTail(lines)
            return tail.count > best.count ? (tail, "") : (best, "")
        }
        return (fallbackTail(lines), "")
    }

    /// Reads the body of a section starting at a heading line, stopping at the next
    /// end-matter heading (references, acknowledgements, appendix…).
    private static func read(from start: Int, in lines: [String]) -> String {
        var body: [String] = []
        // Some layouts run the text on from the heading: "5. Conclusion We have shown…"
        if let r = lines[start].range(of: "conclusions?\\b|concluding remarks\\b|final remarks\\b",
                                      options: [.regularExpression, .caseInsensitive]) {
            let rest = clean(String(lines[start][r.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :.\u{2014}\u{2013}-")))
            if rest.count > 40 { body.append(rest) }
        }
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            if isEndMatter(line) { break }
            if body.joined(separator: " ").count > 6000 { break }
            if !line.isEmpty { body.append(line) }
            i += 1
        }
        return clean(body.joined(separator: " "))
    }

    private static func conclusionHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count < 90 else {
            // A long line can still be a run-on heading like "5. Conclusions We found that…"
            guard trimmed.range(of: "^\\s*\\d{1,2}[.)]?\\s+conclusion",
                                options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
            return "Conclusion"
        }
        let patterns: [(String, String)] = [
            ("^\\s*(\\d{1,2}[.)]?\\s*|[IVX]{1,4}[.)]\\s*)?conclusions?\\s*$", "Conclusion"),
            ("^\\s*(\\d{1,2}[.)]?\\s*)?conclusions? and (future work|outlook|implications|recommendations)\\s*$", "Conclusion and future work"),
            ("^\\s*(\\d{1,2}[.)]?\\s*)?(discussion and conclusions?|conclusions? and discussion)\\s*$", "Discussion and conclusion"),
            ("^\\s*(\\d{1,2}[.)]?\\s*)?concluding remarks\\s*$", "Concluding remarks"),
            ("^\\s*(\\d{1,2}[.)]?\\s*)?summary and (conclusions?|outlook)\\s*$", "Summary and conclusion"),
            ("^\\s*(\\d{1,2}[.)]?\\s*)?final remarks\\s*$", "Final remarks"),
            ("^\\s*(\\d{1,2}[.)]?\\s*)?conclusions?\\b.{0,60}$", "Conclusion"),
        ]
        for (p, label) in patterns
        where trimmed.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil {
            return label
        }
        return nil
    }

    private static func isEndMatter(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard !l.isEmpty, l.count < 80 else { return false }
        let stops = ["references", "reference list", "bibliography", "acknowledgment",
                     "acknowledgement", "acknowledgments", "acknowledgements", "appendix",
                     "funding", "conflict of interest", "competing interests", "declaration",
                     "author contributions", "data availability", "supplementary",
                     "about the authors", "notes"]
        for stop in stops where l.hasPrefix(stop) { return true }
        return false
    }

    /// When a paper has no conclusion heading at all — common in HCI and design venues —
    /// the closing paragraphs before the reference list are the next best thing, and the UI
    /// labels them as such rather than pretending they are a conclusion.
    private static func fallbackTail(_ lines: [String]) -> String {
        guard let refs = lines.lastIndex(where: { isEndMatter($0) }) else { return "" }
        var body: [String] = []
        var i = refs - 1
        while i >= 0, body.joined(separator: " ").count < 1200 {
            let line = lines[i]
            if isSectionHeading(line) && !body.isEmpty { break }
            if !line.isEmpty { body.insert(line, at: 0) }
            i -= 1
        }
        return clean(body.joined(separator: " "))
    }

    private static func isSectionHeading(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count < 70, !t.isEmpty else { return false }
        return t.range(of: "^\\s*(\\d{1,2}([.)]\\d{0,2})*[.)]?|[IVX]{1,4}[.)])\\s+\\S",
                       options: .regularExpression) != nil
    }

    // MARK: - Text hygiene

    /// PDF text layers arrive with hard line wraps, hyphenated word breaks, ligatures and
    /// running heads. All of that has to go before the text is readable in a list.
    private static func normalisedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00AD}", with: "")     // soft hyphen
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !isRunningHead($0) }
    }

    private static func isRunningHead(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }
        if t.range(of: "^\\d{1,4}$", options: .regularExpression) != nil { return true }   // page number
        let lower = t.lowercased()
        return lower.hasPrefix("downloaded from")
            || lower.hasPrefix("this content downloaded")
            || lower.contains("all use subject to https://about.jstor.org/terms")
    }

    static func clean(_ s: String) -> String {
        var t = s
        // Re-join words split across a line break: "naviga- tion" → "navigation".
        t = t.replacingOccurrences(of: "([a-z])-\\s+([a-z])", with: "$1$2", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for (lig, plain) in [("ﬁ", "fi"), ("ﬂ", "fl"), ("ﬀ", "ff"), ("ﬃ", "ffi"), ("ﬄ", "ffl")] {
            t = t.replacingOccurrences(of: lig, with: plain)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
