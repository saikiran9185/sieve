import Foundation

// Small JSON helpers, local to this file.
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
    for p in ["https://doi.org/", "http://doi.org/", "doi:", "https://dx.doi.org/"] where d.hasPrefix(p) {
        d.removeFirst(p.count)
    }
    return d.trimmingCharacters(in: .whitespaces)
}
private func stripTags(_ s: String) -> String {
    s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
     .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
     .trimmingCharacters(in: .whitespacesAndNewlines)
}
private func yearOf(_ s: String) -> Int? { Int(s.prefix(4)) }

// MARK: - PubMed  (NCBI E-utilities — the actual MEDLINE index, free, no key)

struct PubMedProvider: SearchProvider {
    let name = "PubMed"
    let blurb = "MEDLINE · biomedical and life sciences"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        // Two calls: esearch returns PMIDs, esummary turns them into records.
        var s1 = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json"
        s1 += "&retmax=\(limit)&term=\(Net.enc(query))&sort=relevance&tool=Sieve"
        if !email.isEmpty { s1 += "&email=\(Net.enc(email))" }
        guard let u1 = URL(string: s1) else { return [] }
        let ids = arr(dict(dict(try await Net.json(u1))["esearchresult"])["idlist"]).map { str($0) }
        guard !ids.isEmpty else { return [] }

        var s2 = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&tool=Sieve"
        s2 += "&id=\(ids.joined(separator: ","))"
        if !email.isEmpty { s2 += "&email=\(Net.enc(email))" }
        guard let u2 = URL(string: s2) else { return [] }
        let result = dict(dict(try await Net.json(u2))["result"])

        return ids.compactMap { pmid -> SearchHit? in
            let r = dict(result[pmid])
            let title = stripTags(str(r["title"]))
            guard !title.isEmpty else { return nil }
            var doi = "", pmc = ""
            for idObj in arr(r["articleids"]) {
                let d = dict(idObj)
                if str(d["idtype"]) == "doi" { doi = cleanDOI(str(d["value"])) }
                if str(d["idtype"]) == "pmcid" { pmc = str(d["value"]) }
            }
            let pubdate = str(r["pubdate"])
            var hit = SearchHit(
                id: "pubmed:" + pmid,
                title: title,
                authors: arr(r["authors"]).map { str(dict($0)["name"]) }.filter { !$0.isEmpty },
                year: yearOf(pubdate),
                venue: str(r["fulljournalname"]).isEmpty ? str(r["source"]) : str(r["fulljournalname"]),
                doi: doi,
                abstract: "",   // esummary carries no abstract; OpenAlex/Europe PMC fill it in on merge
                url: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/",
                // PubMed Central hosts the free full text when the article is open.
                pdfURL: pmc.isEmpty ? "" : "https://www.ncbi.nlm.nih.gov/pmc/articles/\(pmc)/pdf/",
                provider: name,
                oaStatus: pmc.isEmpty ? "" : "green",
                citedBy: 0)
            hit.pubDate = pubdate
            hit.docType = arr(r["pubtype"]).first.map { str($0) } ?? ""
            hit.language = arr(r["lang"]).first.map { str($0) } ?? ""
            return hit
        }
    }
}

// MARK: - CORE  (aggregates open-access repositories worldwide — every hit has a free PDF)

struct COREProvider: SearchProvider {
    let name = "CORE"
    let blurb = "Open-access repositories worldwide · free PDF on nearly every hit"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        // Trailing slash matters: without it the API 301s and the body is lost.
        let s = "https://api.core.ac.uk/v3/search/works/?q=\(Net.enc(query))&limit=\(min(limit, 100))"
        guard let url = URL(string: s) else { return [] }
        let key = Secrets.get("sieve.corekey")
        let headers = key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"]
        let root = dict(try await Net.json(url, headers: headers, retryOn429: 1))
        return arr(root["results"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(str(w["title"]))
            guard !title.isEmpty else { return nil }
            let pdf = str(w["downloadUrl"])
            var hit = SearchHit(
                id: "core:" + String(num(w["id"]) ?? 0),
                title: title,
                authors: arr(w["authors"]).map { str(dict($0)["name"]) }.filter { !$0.isEmpty },
                year: num(w["yearPublished"]),
                venue: str(w["publisher"]),
                doi: cleanDOI(str(w["doi"])),
                abstract: stripTags(str(w["abstract"])),
                url: str(w["doi"]).isEmpty ? pdf : "https://doi.org/\(cleanDOI(str(w["doi"])))",
                pdfURL: pdf,
                provider: name,
                oaStatus: "green",
                citedBy: 0)
            hit.pubDate = str(w["publishedDate"])
            hit.docType = str(w["documentType"])
            hit.language = str(dict(w["language"])["code"])
            return hit
        }
    }

    /// CORE answers without a key; one only lifts the rate limit, so it is read directly
    /// rather than declared as `keyDefault` (which would switch the provider off).
    var signupURL: String? { "https://core.ac.uk/services/api" }
}

// MARK: - OpenAIRE  (European aggregator over thousands of repositories — BASE-like coverage)

struct OpenAIREProvider: SearchProvider {
    let name = "OpenAIRE"
    let blurb = "Aggregates thousands of repositories · closest open stand-in for BASE"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        let s = "https://api.openaire.eu/search/publications?keywords=\(Net.enc(query))&size=\(min(limit, 50))&format=json"
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        let results = arr(dict(dict(root["response"])["results"])["result"])

        return results.compactMap { item -> SearchHit? in
            let meta = dict(dict(dict(dict(item)["metadata"])["oaf:entity"])["oaf:result"])
            let title = stripTags(Self.text(meta["title"]))
            guard !title.isEmpty else { return nil }
            let creators = Self.list(meta["creator"]).map { Self.text($0) }.filter { !$0.isEmpty }
            let pids = Self.list(meta["pid"])
            var doi = ""
            for p in pids {
                let d = dict(p)
                if str(dict(d["@classid"])["$"]) == "doi" || str(d["@classid"]) == "doi" { doi = cleanDOI(Self.text(p)) }
            }
            if doi.isEmpty, let first = pids.first { doi = cleanDOI(Self.text(first)) }
            if !doi.hasPrefix("10.") { doi = "" }
            let date = Self.text(meta["dateofacceptance"])
            var pdf = ""
            for inst in Self.list(meta["children"]) {
                let url = Self.text(dict(dict(inst)["instance"])["webresource"])
                if url.lowercased().hasSuffix(".pdf") { pdf = url; break }
            }
            var hit = SearchHit(
                id: "openaire:" + (doi.isEmpty ? String(title.prefix(40)) : doi),
                title: title,
                authors: creators,
                year: yearOf(date),
                venue: Self.text(meta["publisher"]),
                doi: doi,
                abstract: stripTags(Self.text(meta["description"])),
                url: doi.isEmpty ? "" : "https://doi.org/\(doi)",
                pdfURL: pdf,
                provider: name,
                oaStatus: "green",
                citedBy: 0)
            hit.pubDate = date
            return hit
        }
    }

    /// OpenAIRE wraps every scalar as {"$": value} and collapses single-element arrays,
    /// so both shapes have to be unwrapped everywhere.
    static func text(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let d = any as? [String: Any] {
            if let v = d["$"] { return text(v) }
            if let v = d["value"] { return text(v) }
            return ""
        }
        if let a = any as? [Any] { return a.first.map { text($0) } ?? "" }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    static func list(_ any: Any?) -> [Any] {
        if let a = any as? [Any] { return a }
        if let d = any as? [String: Any] { return [d] }
        return []
    }
}

// MARK: - PLOS  (fully open-access science journals, Solr-backed)

struct PLOSProvider: SearchProvider {
    let name = "PLOS"
    let blurb = "Fully open-access science journals"

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        var s = "https://api.plos.org/search?q=\(Net.enc(query))&rows=\(min(limit, 100))&wt=json"
        s += "&fl=id,title_display,author_display,journal,publication_date,abstract"
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        return arr(dict(root["response"])["docs"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(str(w["title_display"]))
            let doi = cleanDOI(str(w["id"]))
            guard !title.isEmpty, doi.hasPrefix("10.") else { return nil }
            let date = str(w["publication_date"])
            var hit = SearchHit(
                id: "plos:" + doi,
                title: title,
                authors: arr(w["author_display"]).map { str($0) },
                year: yearOf(date),
                venue: str(w["journal"]),
                doi: doi,
                abstract: stripTags(arr(w["abstract"]).map { str($0) }.joined(separator: " ")),
                url: "https://doi.org/\(doi)",
                pdfURL: "https://journals.plos.org/plosone/article/file?id=\(doi)&type=printable",
                provider: name,
                oaStatus: "gold",
                citedBy: 0)
            hit.pubDate = date
            return hit
        }
    }
}

// MARK: - Key-gated publisher APIs

/// IEEE Xplore. A free key is issued to individuals from the developer portal.
struct IEEEProvider: SearchProvider {
    let name = "IEEE Xplore"
    let blurb = "Engineering, CS, electronics · needs a free API key"
    var keyDefault: String? { "sieve.ieeekey" }
    var signupURL: String? { "https://developer.ieee.org/" }

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        guard !apiKey.isEmpty else { return [] }
        var s = "https://ieeexploreapi.ieee.org/api/v1/search/articles?apikey=\(apiKey)"
        s += "&querytext=\(Net.enc(query))&max_records=\(min(limit, 200))&format=json"
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        return arr(root["articles"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(str(w["title"]))
            guard !title.isEmpty else { return nil }
            let authors = arr(dict(w["authors"])["authors"]).map { str(dict($0)["full_name"]) }.filter { !$0.isEmpty }
            var hit = SearchHit(
                id: "ieee:" + str(w["article_number"]),
                title: title,
                authors: authors,
                year: num(w["publication_year"]),
                venue: str(w["publication_title"]),
                doi: cleanDOI(str(w["doi"])),
                abstract: stripTags(str(w["abstract"])),
                url: str(w["html_url"]),
                pdfURL: str(w["access_type"]) == "OPEN_ACCESS" ? str(w["pdf_url"]) : "",
                provider: name,
                oaStatus: str(w["access_type"]) == "OPEN_ACCESS" ? "gold" : "",
                citedBy: num(w["citing_paper_count"]) ?? 0)
            hit.pubDate = str(w["publication_date"])
            hit.docType = str(w["content_type"])
            return hit
        }
    }
}

/// SpringerLink. Springer Nature issues free keys with a generous daily quota.
struct SpringerProvider: SearchProvider {
    let name = "SpringerLink"
    let blurb = "Broad multidisciplinary · needs a free API key"
    var keyDefault: String? { "sieve.springerkey" }
    var signupURL: String? { "https://dev.springernature.com/" }

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        guard !apiKey.isEmpty else { return [] }
        let s = "https://api.springernature.com/meta/v2/json?q=\(Net.enc(query))&p=\(min(limit, 100))&api_key=\(apiKey)"
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url))
        return arr(root["records"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(str(w["title"]))
            guard !title.isEmpty else { return nil }
            var link = ""
            for l in arr(w["url"]) where str(dict(l)["format"]).isEmpty { link = str(dict(l)["value"]) }
            let date = str(w["publicationDate"])
            var hit = SearchHit(
                id: "springer:" + str(w["identifier"]),
                title: title,
                authors: arr(w["creators"]).map { str(dict($0)["creator"]) }.filter { !$0.isEmpty },
                year: yearOf(date),
                venue: str(w["publicationName"]),
                doi: cleanDOI(str(w["doi"])),
                abstract: stripTags(str(w["abstract"])),
                url: link,
                pdfURL: str(w["openaccess"]) == "true" && !str(w["doi"]).isEmpty
                    ? "https://link.springer.com/content/pdf/\(str(w["doi"])).pdf" : "",
                provider: name,
                oaStatus: str(w["openaccess"]) == "true" ? "gold" : "",
                citedBy: 0)
            hit.pubDate = date
            hit.docType = str(w["contentType"])
            hit.language = str(w["language"])
            return hit
        }
    }
}

/// ScienceDirect (Elsevier). Keys are free but full-text access follows your institution.
struct ElsevierProvider: SearchProvider {
    let name = "ScienceDirect"
    let blurb = "Elsevier · science, tech, medicine · needs a free API key"
    var keyDefault: String? { "sieve.elsevierkey" }
    var signupURL: String? { "https://dev.elsevier.com/" }

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        guard !apiKey.isEmpty else { return [] }
        let s = "https://api.elsevier.com/content/search/sciencedirect?query=\(Net.enc(query))&count=\(min(limit, 100))"
        guard let url = URL(string: s) else { return [] }
        let root = dict(try await Net.json(url, headers: ["X-ELS-APIKey": apiKey, "Accept": "application/json"]))
        return arr(dict(root["search-results"])["entry"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(str(w["dc:title"]))
            guard !title.isEmpty else { return nil }
            let date = str(w["prism:coverDate"])
            var hit = SearchHit(
                id: "elsevier:" + str(w["dc:identifier"]),
                title: title,
                authors: [str(w["dc:creator"])].filter { !$0.isEmpty },
                year: yearOf(date),
                venue: str(w["prism:publicationName"]),
                doi: cleanDOI(str(w["prism:doi"])),
                abstract: "",
                url: str(w["prism:url"]),
                pdfURL: str(w["openaccess"]) == "true" ? str(w["prism:url"]) : "",
                provider: name,
                oaStatus: str(w["openaccess"]) == "true" ? "gold" : "",
                citedBy: 0)
            hit.pubDate = date
            return hit
        }
    }
}

/// Lens.org. Scholarly + patent search; the free academic token must be requested.
struct LensProvider: SearchProvider {
    let name = "Lens.org"
    let blurb = "Scholarly + patents · needs an access token"
    var keyDefault: String? { "sieve.lenskey" }
    var signupURL: String? { "https://www.lens.org/lens/user/subscriptions#scholar" }

    func search(_ query: String, limit: Int, email: String) async throws -> [SearchHit] {
        guard !apiKey.isEmpty, let url = URL(string: "https://api.lens.org/scholarly/search") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "query": ["match": ["title": query]],
            "size": min(limit, 50),
            "include": ["lens_id", "title", "authors", "year_published", "abstract",
                        "external_ids", "source", "scholarly_citations_count", "date_published"]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await Net.session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "Sieve", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from Lens.org"])
        }
        let root = dict(try JSONSerialization.jsonObject(with: data))
        return arr(root["data"]).compactMap { item -> SearchHit? in
            let w = dict(item)
            let title = stripTags(str(w["title"]))
            guard !title.isEmpty else { return nil }
            var doi = ""
            for e in arr(w["external_ids"]) where str(dict(e)["type"]) == "doi" {
                doi = cleanDOI(arr(dict(e)["value"]).first.map { str($0) } ?? "")
            }
            let authors = arr(w["authors"]).map { a -> String in
                let d = dict(a)
                return [str(d["first_name"]), str(d["last_name"])].filter { !$0.isEmpty }.joined(separator: " ")
            }.filter { !$0.isEmpty }
            var hit = SearchHit(
                id: "lens:" + str(w["lens_id"]),
                title: title,
                authors: authors,
                year: num(w["year_published"]),
                venue: str(dict(w["source"])["title"]),
                doi: doi,
                abstract: stripTags(str(w["abstract"])),
                url: doi.isEmpty ? "https://www.lens.org/lens/scholar/article/\(str(w["lens_id"]))"
                                 : "https://doi.org/\(doi)",
                pdfURL: "",
                provider: name,
                oaStatus: "",
                citedBy: num(w["scholarly_citations_count"]) ?? 0)
            hit.pubDate = str(w["date_published"])
            return hit
        }
    }
}
