import Foundation
// Off Apple platforms, swift-corelibs-foundation ships XMLParser in its own module.
// arXiv's Atom feed is parsed with it, so the Windows and Linux builds need this.
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One academic database Sieve can query. All six run concurrently against a single
/// query string and their results get merged into one deduplicated list.
public protocol SearchProvider: Sendable {
    var name: String { get }
    var blurb: String { get }
    /// UserDefaults key holding this provider's API key, when it needs one. Providers that
    /// need a key stay switched off until you paste one in Settings, rather than failing
    /// silently on every search.
    var keyDefault: String? { get }
    var signupURL: String? { get }
    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit]
}

public extension SearchProvider {
    var keyDefault: String? { nil }
    var signupURL: String? { nil }
    /// Read from the Keychain, never from the preferences plist.
    var apiKey: String {
        guard let k = keyDefault else { return "" }
        return Secrets.get(k)
    }
    var needsKey: Bool { keyDefault != nil }
    var isReady: Bool { !needsKey || !apiKey.isEmpty }
}

/// Sites with no usable API — Google Scholar and BASE forbid or block automated querying,
/// and the big publishers gate search behind institutional agreements. Sieve builds the
/// search URL, opens it in your browser, and takes the .bib or .ris you export back.
public struct ExternalSite: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let blurb: String
    public let template: String   // {q} is replaced by the query
    public let howTo: String

    public func url(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: template.replacingOccurrences(of: "{q}", with: q))
    }

    public static let all: [ExternalSite] = [
        ExternalSite(id: "gscholar", name: "Google Scholar",
                     blurb: "Broadest free index — but no API, and automated querying is against its terms",
                     template: "https://scholar.google.com/scholar?q={q}",
                     howTo: "Click the quote icon under a result → BibTeX → save the file → drop it into Sieve."),
        ExternalSite(id: "base", name: "BASE",
                     blurb: "300M+ open-access documents · API is IP-restricted to registered institutions",
                     template: "https://www.base-search.net/Search/Results?lookfor={q}",
                     howTo: "Tick results → Export → RIS → drop the file into Sieve."),
        ExternalSite(id: "ieee", name: "IEEE Xplore",
                     blurb: "Engineering, CS, electronics · use your library login",
                     template: "https://ieeexplore.ieee.org/search/searchresult.jsp?queryText={q}",
                     howTo: "Select results → Export → Citations → BibTeX."),
        ExternalSite(id: "acm", name: "ACM Digital Library",
                     blurb: "Computing and HCI",
                     template: "https://dl.acm.org/action/doSearch?AllField={q}",
                     howTo: "Select results → Export Citations → BibTeX."),
        ExternalSite(id: "sciencedirect", name: "ScienceDirect",
                     blurb: "Elsevier · science, tech, medicine, social sciences",
                     template: "https://www.sciencedirect.com/search?qs={q}",
                     howTo: "Select results → Export → BibTeX."),
        ExternalSite(id: "springer", name: "SpringerLink",
                     blurb: "Broad multidisciplinary",
                     template: "https://link.springer.com/search?query={q}",
                     howTo: "Open an article → Cite this article → download .bib."),
        ExternalSite(id: "wiley", name: "Wiley Online Library",
                     blurb: "Sciences and humanities",
                     template: "https://onlinelibrary.wiley.com/action/doSearch?AllField={q}",
                     howTo: "Select results → Export Citations → BibTeX."),
        ExternalSite(id: "jstor", name: "JSTOR",
                     blurb: "Humanities, social sciences, older archives",
                     template: "https://www.jstor.org/action/doBasicSearch?Query={q}",
                     howTo: "Select items → Cite this item → Export a RIS file."),
        ExternalSite(id: "tandf", name: "Taylor & Francis",
                     blurb: "Multidisciplinary",
                     template: "https://www.tandfonline.com/action/doSearch?AllField={q}",
                     howTo: "Select results → Download citations → BibTeX."),
        ExternalSite(id: "ssrn", name: "SSRN",
                     blurb: "Social sciences, economics, law · working papers",
                     template: "https://papers.ssrn.com/sol3/results.cfm?txtKey_Words={q}",
                     howTo: "Open a paper → Export → RIS."),
        ExternalSite(id: "biorxiv", name: "bioRxiv / medRxiv",
                     blurb: "Biology and medical preprints · also indexed by Europe PMC above",
                     template: "https://www.biorxiv.org/search/{q}",
                     howTo: "Open a preprint → Info/History → Citation Tools → BibTeX."),
        ExternalSite(id: "oabutton", name: "Open Access Button",
                     blurb: "Finds a legal free copy, or emails the author to request one",
                     template: "https://openaccessbutton.org/request?url={q}",
                     howTo: "Paste a DOI to find a free version or send the author a request."),
    ]
}

public enum Net {
    public static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.httpAdditionalHeaders = ["User-Agent": "Sieve/1.0 (macOS literature review tool)"]
        return URLSession(configuration: c)
    }()

    /// Ceilings on what a remote server can make the app hold in memory. A hostile or
    /// broken endpoint should not be able to stream gigabytes into a research tool.
    public static let maxResponseBytes = 8 * 1024 * 1024        // metadata responses
    public static let maxDownloadBytes = 200 * 1024 * 1024      // a PDF

    public static func json(_ url: URL, headers: [String: String] = [:], retryOn429: Int = 0) async throws -> Any {
        guard let safe = SafeLink.web(url) else { throw badScheme(url) }
        var req = URLRequest(url: safe)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        try check(size: data.count, limit: maxResponseBytes, from: safe)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            if http.statusCode == 429, retryOn429 > 0 {
                try await Task.sleep(nanoseconds: 2_500_000_000)
                return try await json(url, headers: headers, retryOn429: retryOn429 - 1)
            }
            throw NSError(domain: "Sieve", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from \(url.host ?? "server")"])
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    public static func text(_ url: URL) async throws -> Data {
        guard let safe = SafeLink.web(url) else { throw badScheme(url) }
        let (data, _) = try await session.data(from: safe)
        try check(size: data.count, limit: maxResponseBytes, from: safe)
        return data
    }

    /// Downloads a file, refusing anything that is not web traffic or is implausibly large.
    public static func download(_ url: URL, limit: Int = maxDownloadBytes) async throws -> Data {
        guard let safe = SafeLink.web(url) else { throw badScheme(url) }
        var req = URLRequest(url: safe)
        req.timeoutInterval = 90
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "Sieve", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from \(safe.host ?? "server")"])
        }
        try check(size: data.count, limit: limit, from: safe)
        return data
    }

    private static func check(size: Int, limit: Int, from url: URL) throws {
        guard size <= limit else {
            throw NSError(domain: "Sieve", code: 413, userInfo: [NSLocalizedDescriptionKey:
                "\(url.host ?? "That server") sent more than \(limit / 1024 / 1024) MB — refused."])
        }
    }

    private static func badScheme(_ url: URL) -> NSError {
        NSError(domain: "Sieve", code: 400, userInfo: [NSLocalizedDescriptionKey:
            "Refused to open “\(url.scheme ?? "?")://” — Sieve only makes ordinary web requests."])
    }

    public static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

private func str(_ any: Any?) -> String { (any as? String) ?? "" }
private func dict(_ any: Any?) -> [String: Any] { (any as? [String: Any]) ?? [:] }
private func arr(_ any: Any?) -> [Any] { (any as? [Any]) ?? [] }
private func num(_ any: Any?) -> Int? {
    if let i = any as? Int { return i }
    if let d = any as? Double { return Int(d) }
    if let s = any as? String { return Int(s) }
    return nil
}

private func cleanDOI(_ s: String) -> String {
    var d = s.lowercased()
    for p in ["https://doi.org/", "http://doi.org/", "doi:", "https://dx.doi.org/"] {
        if d.hasPrefix(p) { d.removeFirst(p.count) }
    }
    return d.trimmingCharacters(in: .whitespaces)
}

private func stripTags(_ s: String) -> String {
    s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
     .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
     .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - OpenAlex  (250M works, open metadata, tells you where the free PDF is)

struct OpenAlexProvider: SearchProvider {
    let name = "OpenAlex"
    let blurb = "250M works · open metadata · finds the free PDF"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        var s = "https://api.openalex.org/works?search=\(Net.enc(query))&per-page=\(limit)"
        if !email.isEmpty { s += "&mailto=\(Net.enc(email))" }
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        return arr(root["results"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = str(w["display_name"] ?? w["title"])
            guard !title.isEmpty else { return nil }
            let authors = arr(w["authorships"]).map { str(dict(dict($0)["author"])["display_name"]) }
                .filter { !$0.isEmpty }
            let oa = dict(w["best_oa_location"] ?? w["primary_location"])
            let host = dict(oa["source"])
            var hit = SearchHit(
                id: str(w["id"]),
                title: stripTags(title),
                authors: authors,
                year: num(w["publication_year"]),
                venue: str(host["display_name"]),
                doi: cleanDOI(str(w["doi"])),
                abstract: OpenAlex.invertedAbstract(w["abstract_inverted_index"]),
                url: str(w["doi"]).isEmpty ? str(oa["landing_page_url"]) : str(w["doi"]),
                pdfURL: str(oa["pdf_url"]),
                provider: name,
                oaStatus: str(dict(w["open_access"])["oa_status"]),
                citedBy: num(w["cited_by_count"]) ?? 0)
            hit.sdgs = arr(w["sustainable_development_goals"]).compactMap { g in
                let d = dict(g)
                // Only keep a goal the classifier is reasonably sure about.
                return ((d["score"] as? Double) ?? 0) >= 0.4 ? str(d["display_name"]) : nil
            }
            hit.pubDate = str(w["publication_date"])
            hit.docType = str(w["type"])
            hit.language = str(w["language"])
            hit.openAlexId = str(w["id"]).replacingOccurrences(of: "https://openalex.org/", with: "")
            hit.references = arr(w["referenced_works"]).map {
                str($0).replacingOccurrences(of: "https://openalex.org/", with: "")
            }
            return hit
        }
    }

    /// OpenAlex ships abstracts as an inverted index for licensing reasons; rebuild the prose.
}

// MARK: - Crossref  (the DOI registry — authoritative bibliographic record)

struct CrossrefProvider: SearchProvider {
    let name = "Crossref"
    let blurb = "The DOI registry · authoritative citations"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        var s = "https://api.crossref.org/works?query=\(Net.enc(query))&rows=\(limit)&select=DOI,title,author,issued,container-title,abstract,URL,is-referenced-by-count,link"
        if !email.isEmpty { s += "&mailto=\(Net.enc(email))" }
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        return arr(dict(root["message"])["items"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(arr(w["title"]).compactMap { $0 as? String }.first ?? "")
            guard !title.isEmpty else { return nil }
            let authors = arr(w["author"]).map { a -> String in
                let d = dict(a)
                return [str(d["given"]), str(d["family"])].filter { !$0.isEmpty }.joined(separator: " ")
            }.filter { !$0.isEmpty }
            let year = arr(dict(w["issued"])["date-parts"]).first.flatMap { num(arr($0).first) }
            let pdf = arr(w["link"]).first { str(dict($0)["content-type"]) == "application/pdf" }
                .map { str(dict($0)["URL"]) } ?? ""
            return SearchHit(
                id: "crossref:" + str(w["DOI"]),
                title: title,
                authors: authors,
                year: year,
                venue: arr(w["container-title"]).compactMap { $0 as? String }.first ?? "",
                doi: cleanDOI(str(w["DOI"])),
                abstract: stripTags(str(w["abstract"])),
                url: str(w["URL"]),
                pdfURL: pdf,
                provider: name,
                oaStatus: "",
                citedBy: num(w["is-referenced-by-count"]) ?? 0)
        }
    }
}

// MARK: - arXiv  (preprints — always a free PDF)

struct ArxivProvider: SearchProvider {
    let name = "arXiv"
    let blurb = "Preprints · every result has a free PDF"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        // https only: the http endpoint 301s and the redirect comes back empty.
        let terms = query.split(separator: " ").map { Net.enc(String($0)) }.joined(separator: "+")
        let s = "https://export.arxiv.org/api/query?search_query=all:\(terms)&start=0&max_results=\(limit)&sortBy=relevance"
        guard let url = URL(string: s) else { return [] }
        let data = try await Net.text(url)
        return AtomParser.parse(data, provider: name)
    }
}

/// arXiv answers in Atom XML, not JSON — a small streaming parser keeps it dependency-free.
final class AtomParser: NSObject, XMLParserDelegate {
    private var hits: [SearchHit] = []
    private var element = ""
    private var buffer = ""
    private var inEntry = false
    private var cur = (title: "", summary: "", id: "", published: "", pdf: "", journal: "", doi: "")
    private var authors: [String] = []
    private var inAuthor = false
    private let provider: String

    init(provider: String) { self.provider = provider }

    static func parse(_ data: Data, provider: String) -> [SearchHit] {
        let p = AtomParser(provider: provider)
        let parser = XMLParser(data: data)
        // Explicit, though this is already the platform default: never fetch anything a
        // document references. Untrusted XML must not be able to make the app open a file
        // or reach a network host of its choosing.
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = p
        parser.parse()
        return p.hits
    }

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        element = e; buffer = ""
        if e == "entry" {
            inEntry = true
            cur = ("", "", "", "", "", "", ""); authors = []
        }
        if e == "author" { inAuthor = true }
        if e == "link", inEntry, a["type"] == "application/pdf" { cur.pdf = a["href"] ?? "" }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { buffer += s }

    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        let v = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inEntry else { buffer = ""; return }
        switch e {
        case "title":     cur.title = v.replacingOccurrences(of: "\n", with: " ")
        case "summary":   cur.summary = v.replacingOccurrences(of: "\n", with: " ")
        case "id":        cur.id = v
        case "published": cur.published = v
        case "name":      if inAuthor, !v.isEmpty { authors.append(v) }
        case "author":    inAuthor = false
        case "journal_ref": cur.journal = v
        case "doi":       cur.doi = v
        case "entry":
            inEntry = false
            let year = Int(cur.published.prefix(4))
            var pdf = cur.pdf
            if pdf.isEmpty, cur.id.contains("/abs/") { pdf = cur.id.replacingOccurrences(of: "/abs/", with: "/pdf/") }
            if !cur.title.isEmpty {
                hits.append(SearchHit(id: cur.id, title: cur.title, authors: authors, year: year,
                                      venue: cur.journal.isEmpty ? "arXiv preprint" : cur.journal,
                                      doi: cur.doi.lowercased(), abstract: cur.summary,
                                      url: cur.id, pdfURL: pdf, provider: provider,
                                      oaStatus: "green", citedBy: 0))
            }
        default: break
        }
        buffer = ""
    }
}

// MARK: - Semantic Scholar  (strong on CS/HCI, gives citation counts and TLDRs)

struct SemanticScholarProvider: SearchProvider {
    let name = "Semantic Scholar"
    let blurb = "Strong on CS & design · needs a free API key"
    var keyDefault: String? { "sieve.s2key" }
    var signupURL: String? { "https://www.semanticscholar.org/product/api#api-key-form" }

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        let fields = "title,abstract,year,venue,authors,externalIds,openAccessPdf,citationCount,url"
        let s = "https://api.semanticscholar.org/graph/v1/paper/search?query=\(Net.enc(query))&limit=\(min(limit, 100))&fields=\(fields)"
        guard let url = URL(string: s) else { return [] }
        let headers = apiKey.isEmpty ? [:] : ["x-api-key": apiKey]
        let root = dict(try await Net.json(url, headers: headers, retryOn429: apiKey.isEmpty ? 2 : 0))
        return arr(root["data"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = str(w["title"])
            guard !title.isEmpty else { return nil }
            let ext = dict(w["externalIds"])
            return SearchHit(
                id: "s2:" + str(w["paperId"]),
                title: title,
                authors: arr(w["authors"]).map { str(dict($0)["name"]) }.filter { !$0.isEmpty },
                year: num(w["year"]),
                venue: str(w["venue"]),
                doi: cleanDOI(str(ext["DOI"])),
                abstract: str(w["abstract"]),
                url: str(w["url"]),
                pdfURL: str(dict(w["openAccessPdf"])["url"]),
                provider: name,
                oaStatus: dict(w["openAccessPdf"]).isEmpty ? "" : "open",
                citedBy: num(w["citationCount"]) ?? 0)
        }
    }
}

// MARK: - Europe PMC  (covers all of PubMed/MEDLINE plus preprints)

struct EuropePMCProvider: SearchProvider {
    let name = "Europe PMC"
    let blurb = "All of PubMed / MEDLINE + life sciences"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        let s = "https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=\(Net.enc(query))&format=json&pageSize=\(limit)&resultType=core"
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        return arr(dict(root["resultList"])["result"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(str(w["title"]))
            guard !title.isEmpty else { return nil }
            let authors = arr(dict(w["authorList"])["author"]).map { a -> String in
                let d = dict(a)
                let full = str(d["fullName"])
                return full.isEmpty ? [str(d["firstName"]), str(d["lastName"])].joined(separator: " ") : full
            }.filter { !$0.isEmpty }
            var pdf = ""
            for u in arr(dict(w["fullTextUrlList"])["fullTextUrl"]) {
                let d = dict(u)
                if str(d["documentStyle"]) == "pdf" { pdf = str(d["url"]); break }
            }
            let pmcid = str(w["pmcid"])
            if pdf.isEmpty, !pmcid.isEmpty {
                pdf = "https://europepmc.org/articles/\(pmcid)?pdf=render"
            }
            let id = str(w["id"])
            return SearchHit(
                id: "epmc:" + id,
                title: title,
                authors: authors,
                year: num(w["pubYear"]),
                venue: str(w["journalTitle"]),
                doi: cleanDOI(str(w["doi"])),
                abstract: stripTags(str(w["abstractText"])),
                url: str(w["doi"]).isEmpty
                    ? "https://europepmc.org/article/\(str(w["source"]))/\(id)"
                    : "https://doi.org/\(str(w["doi"]))",
                pdfURL: pdf,
                provider: name,
                oaStatus: str(w["isOpenAccess"]) == "Y" ? "gold" : "",
                citedBy: num(w["citedByCount"]) ?? 0)
        }
    }
}

// MARK: - DOAJ  (fully open-access journals — good for design & humanities)

struct DOAJProvider: SearchProvider {
    let name = "DOAJ"
    let blurb = "Open-access journals · design & humanities"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        let s = "https://doaj.org/api/search/articles/\(Net.enc(query))?pageSize=\(min(limit, 100))"
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        return arr(root["results"]).compactMap { item -> SearchHit? in
            let w = dict(dict(item)["bibjson"])
            let title = stripTags(str(w["title"]))
            guard !title.isEmpty else { return nil }
            var doi = "", link = "", pdf = ""
            for ident in arr(w["identifier"]) where str(dict(ident)["type"]) == "doi" {
                doi = cleanDOI(str(dict(ident)["id"]))
            }
            for l in arr(w["link"]) {
                let d = dict(l)
                if str(d["type"]) == "fulltext" {
                    link = str(d["url"])
                    if str(d["content_type"]).lowercased().contains("pdf") { pdf = str(d["url"]) }
                }
            }
            return SearchHit(
                id: "doaj:" + str(dict(item)["id"]),
                title: title,
                authors: arr(w["author"]).map { str(dict($0)["name"]) }.filter { !$0.isEmpty },
                year: num(w["year"]),
                venue: str(dict(w["journal"])["title"]),
                doi: doi,
                abstract: stripTags(str(w["abstract"])),
                url: link.isEmpty ? (doi.isEmpty ? "" : "https://doi.org/\(doi)") : link,
                pdfURL: pdf,
                provider: name,
                oaStatus: "gold",
                citedBy: 0)
        }
    }
}
