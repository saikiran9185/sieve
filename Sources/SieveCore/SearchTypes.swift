import Foundation

// MARK: - Search results (pre-import)

/// One record as a provider returned it, before it becomes a `Paper`.
/// Deliberately free of any Apple framework: this type crosses to Windows and Linux.
public struct SearchHit: Identifiable, Hashable {
    public var id: String                    // provider-native id
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String
    public var doi: String
    public var abstract: String
    public var url: String
    public var pdfURL: String
    public var provider: String
    public var oaStatus: String
    public var citedBy: Int
    public var mergedFrom: [String] = []     // providers that also returned this record
    public var sdgs: [String] = []
    public var pubDate: String = ""
    public var docType: String = ""
    public var language: String = ""
    public var openAlexId: String = ""
    public var references: [String] = []

    public init(
        id: String,
        title: String,
        authors: [String],
        year: Int?,
        venue: String,
        doi: String,
        abstract: String,
        url: String,
        pdfURL: String,
        provider: String,
        oaStatus: String,
        citedBy: Int,
        mergedFrom: [String] = [],
        sdgs: [String] = [],
        pubDate: String = "",
        docType: String = "",
        language: String = "",
        openAlexId: String = "",
        references: [String] = []
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.doi = doi
        self.abstract = abstract
        self.url = url
        self.pdfURL = pdfURL
        self.provider = provider
        self.oaStatus = oaStatus
        self.citedBy = citedBy
        self.mergedFrom = mergedFrom
        self.sdgs = sdgs
        self.pubDate = pubDate
        self.docType = docType
        self.language = language
        self.openAlexId = openAlexId
        self.references = references
    }

    public var dedupeKey: String { Dedupe.key(doi: doi, title: title, year: year) }
}

// MARK: - Deduplication

/// Deciding whether two records are the same paper. DOI is definitive. Otherwise the
/// normalised title carries it: the same article is routinely dated a year apart across
/// databases because of online-first publication, so the year only joins the key when
/// the title is too short to identify a paper on its own.
public enum Dedupe {
    public static func key(doi: String, title: String, year: Int?) -> String {
        let d = doi.trimmingCharacters(in: .whitespaces).lowercased()
        if !d.isEmpty { return "doi:" + d }
        let t = title.lowercased().filter { $0.isLetter || $0.isNumber }
        if t.count >= 25 { return "t:" + String(t.prefix(90)) }
        return "t:" + t + ":" + (year.map(String.init) ?? "")
    }
}
