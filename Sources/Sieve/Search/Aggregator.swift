import Foundation
import AppKit
import SwiftUI

/// Fires one query at every enabled database at the same time, then folds the
/// answers into a single list where each real-world paper appears exactly once.
@MainActor
final class SearchEngine: ObservableObject {
    /// Every database Sieve can query directly. The keyless ones are on by default;
    /// the key-gated ones stay dark until a key is pasted into Settings.
    static let allProviders: [any SearchProvider] = [
        OpenAlexProvider(), CrossrefProvider(), EuropePMCProvider(), PubMedProvider(),
        COREProvider(), OpenAIREProvider(), ArxivProvider(), DOAJProvider(), PLOSProvider(),
        SemanticScholarProvider(), IEEEProvider(), SpringerProvider(),
        ElsevierProvider(), LensProvider()
    ]

    static var defaultEnabled: Set<String> {
        Set(allProviders.filter { !$0.needsKey }.map(\.name))
    }

    @Published var query: String = ""
    @Published var enabled: Set<String> = SearchEngine.defaultEnabled
    @Published var results: [SearchHit] = []
    @Published var running = false
    @Published var progress: [String: ProviderState] = [:]
    @Published var yearFrom: Int? = nil
    @Published var yearTo: Int? = nil
    @Published var dateFrom: Date? = nil
    @Published var dateTo: Date? = nil
    @Published var authorFilter = ""
    @Published var sdgFilter: Set<String> = []
    @Published var onlyWithPDF = false
    @Published var sort: Sort = .relevance
    @Published var perProviderLimit = 25

    enum ProviderState: Equatable {
        case waiting, running, done(Int), failed(String)
        var count: Int { if case .done(let n) = self { return n }; return 0 }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case relevance = "Relevance", newest = "Newest", cited = "Most cited", title = "Title"
        var id: String { rawValue }
    }

    var contactEmail: String {
        UserDefaults.standard.string(forKey: "sieve.contactEmail") ?? ""
    }

    func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        running = true
        results = []
        let active = SearchEngine.allProviders.filter { enabled.contains($0.name) && $0.isReady }
        progress = Dictionary(uniqueKeysWithValues: active.map { ($0.name, .waiting) })
        let email = contactEmail
        let limit = perProviderLimit

        // One concurrent task per database — a slow or broken source never blocks the rest.
        await withTaskGroup(of: (String, Result<[SearchHit], Error>).self) { group in
            for provider in active {
                progress[provider.name] = .running
                group.addTask {
                    do { return (provider.name, .success(try await provider.search(q, limit: limit, email: email))) }
                    catch { return (provider.name, .failure(error)) }
                }
            }
            var collected: [SearchHit] = []
            for await (name, outcome) in group {
                switch outcome {
                case .success(let hits):
                    progress[name] = .done(hits.count)
                    collected += hits
                    results = SearchEngine.merge(collected)   // stream results in as they land
                case .failure(let e):
                    progress[name] = .failed(Self.shortError(e))
                }
            }
            results = SearchEngine.merge(collected)
        }
        running = false
    }

    static func iso(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    static func shortError(_ e: Error) -> String {
        let ns = e as NSError
        if ns.domain == NSURLErrorDomain { return "no connection" }
        if ns.code == 429 { return "rate limited — add a free API key in Settings" }
        if ns.code == 401 || ns.code == 403 { return "key rejected" }
        if ns.code >= 400 && ns.code < 600 { return "HTTP \(ns.code)" }
        return "failed"
    }

    /// Collapse records that describe the same paper. DOI wins; otherwise a normalised
    /// title + year. The surviving record keeps the richest field from each contributor —
    /// so a Crossref record can inherit arXiv's PDF link and OpenAlex's abstract.
    static func merge(_ hits: [SearchHit]) -> [SearchHit] {
        var byKey: [String: SearchHit] = [:]
        var order: [String] = []
        for h in hits {
            let k = h.dedupeKey
            guard var existing = byKey[k] else {
                byKey[k] = h; order.append(k); continue
            }
            if !existing.mergedFrom.contains(h.provider), existing.provider != h.provider {
                existing.mergedFrom.append(h.provider)
            }
            if existing.abstract.count < h.abstract.count { existing.abstract = h.abstract }
            if existing.pdfURL.isEmpty { existing.pdfURL = h.pdfURL }
            if existing.doi.isEmpty { existing.doi = h.doi }
            if existing.venue.isEmpty { existing.venue = h.venue }
            if existing.url.isEmpty { existing.url = h.url }
            if existing.year == nil { existing.year = h.year }
            if existing.authors.count < h.authors.count { existing.authors = h.authors }
            if existing.citedBy < h.citedBy { existing.citedBy = h.citedBy }
            if existing.oaStatus.isEmpty { existing.oaStatus = h.oaStatus }
            if existing.sdgs.isEmpty { existing.sdgs = h.sdgs }
            if existing.pubDate.isEmpty { existing.pubDate = h.pubDate }
            if existing.docType.isEmpty { existing.docType = h.docType }
            if existing.language.isEmpty { existing.language = h.language }
            if existing.openAlexId.isEmpty { existing.openAlexId = h.openAlexId }
            if existing.references.isEmpty { existing.references = h.references }
            byKey[k] = existing
        }
        return order.compactMap { byKey[$0] }
    }

    /// Every SDG the current results mention, for the filter menu.
    var availableSDGs: [String] {
        Array(Set(results.flatMap(\.sdgs))).sorted()
    }

    var filtered: [SearchHit] {
        var out = results
        if let f = yearFrom { out = out.filter { ($0.year ?? 0) >= f } }
        if let t = yearTo { out = out.filter { ($0.year ?? 9999) <= t } }
        if let f = dateFrom {
            let key = SearchEngine.iso(f)
            out = out.filter { $0.pubDate.isEmpty ? true : $0.pubDate >= key }
        }
        if let t = dateTo {
            let key = SearchEngine.iso(t)
            out = out.filter { $0.pubDate.isEmpty ? true : $0.pubDate <= key }
        }
        if !authorFilter.trimmingCharacters(in: .whitespaces).isEmpty {
            let needles = authorFilter.lowercased()
                .split(whereSeparator: { ",;".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            out = out.filter { hit in
                needles.contains { n in hit.authors.contains { $0.lowercased().contains(n) } }
            }
        }
        if !sdgFilter.isEmpty { out = out.filter { !Set($0.sdgs).isDisjoint(with: sdgFilter) } }
        if onlyWithPDF { out = out.filter { !$0.pdfURL.isEmpty } }
        switch sort {
        case .relevance: break
        case .newest: out.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .cited:   out.sort { $0.citedBy > $1.citedBy }
        case .title:   out.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return out
    }
}

// MARK: - Open-access PDF resolution

/// Finds a legal free PDF for a DOI. Tries what the search result already told us,
/// then Unpaywall, then OpenAlex. Never touches paywalled or pirated sources.
enum OAResolver {
    static func resolve(doi: String, knownPDF: String, email: String) async -> String? {
        if !knownPDF.isEmpty { return knownPDF }
        guard !doi.isEmpty else { return nil }

        if !email.isEmpty,
           let u = URL(string: "https://api.unpaywall.org/v2/\(doi)?email=\(Net.enc(email))"),
           let root = try? await Net.json(u) as? [String: Any],
           let loc = root["best_oa_location"] as? [String: Any],
           let pdf = loc["url_for_pdf"] as? String, !pdf.isEmpty {
            return pdf
        }

        if let u = URL(string: "https://api.openalex.org/works/doi:\(doi)"),
           let root = try? await Net.json(u) as? [String: Any],
           let loc = root["best_oa_location"] as? [String: Any],
           let pdf = loc["pdf_url"] as? String, !pdf.isEmpty {
            return pdf
        }
        return nil
    }
}

// MARK: - Downloader

@MainActor
final class Downloader: ObservableObject {
    @Published var active: [Int: String] = [:]     // paperId -> status text

    /// Fetches the PDF into the library folder and links it to the paper.
    /// Verifies the bytes really are a PDF — publisher pages love to serve HTML with a .pdf URL.
    func fetch(paper: Paper, store: Store, email: String) async {
        active[paper.id] = "Finding a free copy…"
        defer { active[paper.id] = nil }

        guard let link = await OAResolver.resolve(doi: paper.doi, knownPDF: paper.pdfURL, email: email),
              let url = SafeLink.web(link) else {
            store.flash("No open-access PDF found for “\(paper.title.prefix(40))…”. Drop the PDF in by hand.")
            return
        }
        active[paper.id] = "Downloading…"
        do {
            let data = try await Net.download(url)
            guard data.count > 1000, data.prefix(5) == Data("%PDF-".utf8) else {
                store.flash("That link returned a web page, not a PDF. Opening it in your browser instead.")
                SafeLink.open(url)
                return
            }
            guard let project = store.project else { return }
            let dir = Library.pdfDir(id: project.id, name: project.name)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(Self.filename(for: paper))
            try data.write(to: dest)
            store.setPDFPath(paper.id, dest.path)
            store.flash("Saved “\(paper.title.prefix(40))…”")
        } catch {
            store.flash("Download failed: \(error.localizedDescription)")
        }
    }

    static func filename(for p: Paper) -> String { PDFNaming.filename(for: p) }
}

