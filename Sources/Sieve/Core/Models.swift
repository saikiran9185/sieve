import Foundation
import SwiftUI

// MARK: - Project

struct Project: Identifiable, Hashable {
    var id: Int
    var name: String
    var question: String = ""
    var inclusionCriteria: String = ""
    var exclusionCriteria: String = ""
    var createdAt: Date = Date()
}

// MARK: - What a record IS, as distinct from what it says

/// A source is anything a review draws on. Separating the source from the evidence inside it
/// is what lets an interview transcript and a journal article sit in the same corpus.
enum SourceType: String, CaseIterable, Identifiable {
    case paper, website, book, chapter, report, thesis, interview, image, video, dataset, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: return "Paper"
        case .website: return "Website"
        case .book: return "Book"
        case .chapter: return "Book chapter"
        case .report: return "Report"
        case .thesis: return "Thesis"
        case .interview: return "Interview"
        case .image: return "Image"
        case .video: return "Video"
        case .dataset: return "Dataset"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .paper: return "doc.text"
        case .website: return "globe"
        case .book: return "book.closed"
        case .chapter: return "book"
        case .report: return "doc.richtext"
        case .thesis: return "graduationcap"
        case .interview: return "waveform"
        case .image: return "photo"
        case .video: return "film"
        case .dataset: return "tablecells"
        case .other: return "square.on.square"
        }
    }
}

/// What a piece of evidence IS. A quote and a statistic are both evidence, but you reason
/// about them differently, and a review reports them differently.
enum EvidenceKind: String, CaseIterable, Identifiable {
    case quote, statistic, observation, finding, definition, image, claim
    var id: String { rawValue }

    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .quote: return "quote.opening"
        case .statistic: return "number"
        case .observation: return "eye"
        case .finding: return "checkmark.seal"
        case .definition: return "character.book.closed"
        case .image: return "photo"
        case .claim: return "flag"
        }
    }
}

/// The single most important distinction in the app: is this what the source says, what I
/// think it means, or something I don't know yet? Conflating the three is how a literature
/// review quietly turns an interpretation into a finding.
enum Stance: String, CaseIterable, Identifiable {
    case evidence, interpretation, question
    var id: String { rawValue }

    var label: String {
        switch self {
        case .evidence: return "Evidence"
        case .interpretation: return "Interpretation"
        case .question: return "Question"
        }
    }

    var blurb: String {
        switch self {
        case .evidence: return "What the source actually says."
        case .interpretation: return "What I think it means."
        case .question: return "What I don't know yet."
        }
    }

    var color: Color {
        switch self {
        case .evidence: return .readable("#4C8DF2")
        case .interpretation: return .readable("#9B6BE8")
        case .question: return .readable("#F2C14E")
        }
    }

    /// The literal colour, used for the highlight drawn into the PDF.
    var rawHex: String {
        switch self {
        case .evidence: return "#4C8DF2"
        case .interpretation: return "#9B6BE8"
        case .question: return "#F2C14E"
        }
    }

    var icon: String {
        switch self {
        case .evidence: return "text.quote"
        case .interpretation: return "brain"
        case .question: return "questionmark.circle"
        }
    }
}

enum Confidence: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var dots: Int { self == .low ? 1 : (self == .medium ? 2 : 3) }
}

/// Where a piece of evidence stands: checked against the source, still to check, or in
/// conflict with something else in the corpus. This is what makes weak spots visible.
enum Verification: String, CaseIterable, Identifiable {
    case unchecked, verified, conflicting
    var id: String { rawValue }

    var label: String {
        switch self {
        case .unchecked: return "Needs checking"
        case .verified: return "Verified against source"
        case .conflicting: return "Conflicting evidence"
        }
    }

    var icon: String {
        switch self {
        case .unchecked: return "questionmark.circle"
        case .verified: return "checkmark.seal.fill"
        case .conflicting: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unchecked: return Palette.slate
        case .verified: return Palette.emerald
        case .conflicting: return Palette.rose
        }
    }
}

// MARK: - Relations

/// A typed, directed link. Relations are what turn a pile of highlights into an argument:
/// this finding supports that claim, this paper contradicts that one.
enum RelationType: String, CaseIterable, Identifiable {
    case supports, contradicts, extends, exampleOf = "example_of", causes, refines, answers, cites
    var id: String { rawValue }

    var label: String {
        switch self {
        case .supports: return "supports"
        case .contradicts: return "contradicts"
        case .extends: return "extends"
        case .exampleOf: return "is an example of"
        case .causes: return "causes"
        case .refines: return "refines"
        case .answers: return "answers"
        case .cites: return "cites"
        }
    }

    var color: Color {
        switch self {
        case .supports, .answers: return Palette.emerald
        case .contradicts: return Palette.rose
        case .extends, .refines: return Palette.accent
        case .exampleOf, .causes: return Palette.violet
        case .cites: return Palette.slate
        }
    }

    var icon: String {
        switch self {
        case .supports: return "plus.circle"
        case .contradicts: return "xmark.circle"
        case .extends: return "arrow.up.right.circle"
        case .exampleOf: return "circle.grid.2x2"
        case .causes: return "arrow.right.circle"
        case .refines: return "scope"
        case .answers: return "checkmark.bubble"
        case .cites: return "quote.bubble"
        }
    }
}

enum NodeKind: String, Codable { case evidence, source }

struct Relation: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var fromKind: String       // NodeKind.rawValue
    var fromId: Int
    var type: String           // RelationType.rawValue
    var toKind: String
    var toId: Int
    var note: String = ""
    var createdAt: Date = Date()

    var relation: RelationType { RelationType(rawValue: type) ?? .supports }
}

// MARK: - Method

/// One step in a methodology. A method is just an ordered list of these, so a researcher can
/// build the process their discipline actually uses instead of adopting the app's.
enum MethodBlock: String, CaseIterable, Identifiable, Codable {
    case search, importSources = "import", screen, retrieve, read, highlight, code, tag,
         memo, cluster, compare, relate, vote, rank, extract, synthesize, validate, export
    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: return "Search"
        case .importSources: return "Import"
        case .screen: return "Screen"
        case .retrieve: return "Retrieve full texts"
        case .read: return "Read"
        case .highlight: return "Highlight"
        case .code: return "Code"
        case .tag: return "Tag"
        case .memo: return "Memo"
        case .cluster: return "Cluster"
        case .compare: return "Compare"
        case .relate: return "Relate"
        case .vote: return "Vote"
        case .rank: return "Rank"
        case .extract: return "Extract"
        case .synthesize: return "Synthesize"
        case .validate: return "Validate"
        case .export: return "Export"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .importSources: return "square.and.arrow.down"
        case .screen: return "checklist"
        case .retrieve: return "arrow.down.doc"
        case .read: return "book"
        case .highlight: return "highlighter"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .tag: return "tag"
        case .memo: return "note.text"
        case .cluster: return "circle.grid.3x3"
        case .compare: return "rectangle.split.2x1"
        case .relate: return "point.3.connected.trianglepath.dotted"
        case .vote: return "hand.thumbsup"
        case .rank: return "list.number"
        case .extract: return "tablecells"
        case .synthesize: return "doc.append"
        case .validate: return "checkmark.shield"
        case .export: return "square.and.arrow.up"
        }
    }

    /// Which screen this step opens. Some steps are ways of working rather than places,
    /// and those point at the screen where the work happens.
    var section: String {
        switch self {
        case .search: return "search"
        case .importSources: return "library"
        case .screen, .vote: return "screening"
        case .retrieve: return "library"
        case .read, .highlight, .code, .memo: return "reader"
        case .tag: return "tags"
        case .cluster, .relate: return "map"
        case .compare, .extract, .rank: return "matrix"
        case .synthesize, .validate: return "evidence"
        case .export: return "prisma"
        }
    }

    var blurb: String {
        switch self {
        case .search: return "Query databases for candidate sources."
        case .importSources: return "Bring in PDFs, .bib/.ris files, or your own material."
        case .screen: return "Decide what is in and what is out, with reasons."
        case .retrieve: return "Get the full texts of what survived screening."
        case .read: return "Read the sources properly."
        case .highlight: return "Mark the passages that matter."
        case .code: return "Attach analytic codes to passages."
        case .tag: return "Set up the categories you code with."
        case .memo: return "Write your own thinking alongside the evidence."
        case .cluster: return "Group codes into themes."
        case .compare: return "Set findings side by side."
        case .relate: return "Link evidence that supports or contradicts other evidence."
        case .vote: return "Rate or vote on what to include."
        case .rank: return "Order sources by importance."
        case .extract: return "Pull structured data into the matrix."
        case .synthesize: return "Build the argument from the evidence."
        case .validate: return "Check claims against their sources."
        case .export: return "Produce the report, diagram and data files."
        }
    }
}

struct Method: Identifiable, Hashable {
    var id: Int
    var projectId: Int?        // nil = a reusable recipe available to every review
    var name: String
    var detail: String = ""
    var blocks: [MethodBlock] = []
    var isTemplate: Bool = false
    var currentStep: Int = 0
}

// MARK: - Folder

/// A folder inside a review. Folders nest, so a project can be organised the way the
/// research actually is — by theme, by chapter, by methodology, however you think.
struct Folder: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var parentId: Int?
    var name: String
    var colorHex: String = "#8A93A3"
    var sortOrder: Int = 0

    var color: Color { Color(hex: colorHex) }
}

// MARK: - PRISMA state machine

/// A record's position in the PRISMA 2020 flow. Each paper holds exactly one stage;
/// the flow diagram counts are derived from these, never stored twice.
enum Stage: String, CaseIterable, Identifiable {
    case identified          // found by a search, not yet triaged
    case duplicate           // removed before screening
    case screening           // title/abstract under review
    case excludedScreening   // excluded at title/abstract
    case sought              // passed T/A, seeking full text
    case notRetrieved        // full text could not be obtained
    case eligibility         // full text being assessed
    case excludedEligibility // excluded at full text (needs a reason)
    case included            // in the review

    var id: String { rawValue }

    var label: String {
        switch self {
        case .identified: return "Identified"
        case .duplicate: return "Duplicate"
        case .screening: return "Screening"
        case .excludedScreening: return "Excluded (title/abstract)"
        case .sought: return "Full text sought"
        case .notRetrieved: return "Not retrieved"
        case .eligibility: return "Full text assessed"
        case .excludedEligibility: return "Excluded (full text)"
        case .included: return "Included"
        }
    }

    var short: String {
        switch self {
        case .identified: return "New"
        case .duplicate: return "Dup"
        case .screening: return "Screening"
        case .excludedScreening: return "Excl · T/A"
        case .sought: return "Sought"
        case .notRetrieved: return "No PDF"
        case .eligibility: return "Full text"
        case .excludedEligibility: return "Excl · FT"
        case .included: return "Included"
        }
    }

    var color: Color {
        switch self {
        case .identified: return Palette.slate
        case .duplicate: return Palette.slate
        case .screening: return Palette.amber
        case .excludedScreening, .excludedEligibility, .notRetrieved: return Palette.rose
        case .sought, .eligibility: return Palette.violet
        case .included: return Palette.emerald
        }
    }

    var isExcluded: Bool {
        self == .excludedScreening || self == .excludedEligibility || self == .duplicate || self == .notRetrieved
    }
}

// MARK: - Paper

struct Paper: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var title: String
    var authors: [String] = []
    var year: Int?
    var venue: String = ""
    var doi: String = ""
    var abstract: String = ""
    var url: String = ""              // landing page / canonical link
    var pdfURL: String = ""           // direct open-access PDF link, if known
    var pdfPath: String = ""          // local file in the library
    var sourceDB: String = ""         // OpenAlex / Crossref / arXiv / … / Manual
    var sourceQuery: String = ""      // the search that surfaced it — provenance
    var oaStatus: String = ""
    var citedBy: Int = 0
    var addedAt: Date = Date()
    var accessedAt: Date?             // when the PDF was actually retrieved
    var stage: Stage = .identified
    var excludeReason: String = ""
    var notes: String = ""
    var starred: Bool = false
    var dedupeKey: String = ""
    var folderId: Int? = nil
    var conclusion: String = ""          // what this paper concludes, in your words
    var toRead: String = ""              // the part you still need to read
    var sdgs: [String] = []              // UN Sustainable Development Goals, from OpenAlex
    var pubDate: String = ""             // full ISO date when the source gives one
    var docType: String = ""             // article / book-chapter / preprint …
    var language: String = ""
    var openAlexId: String = ""
    var references: [String] = []        // OpenAlex ids this paper cites — builds the map
    var sourceType: SourceType = .paper
    var keywords: [String] = []          // read out of the PDF, or supplied by the database
    var extractedConclusion: String = "" // the paper's own conclusion section, verbatim
    var conclusionHeading: String = ""   // empty when it is only the closing paragraphs
    var reportCount: Int = 1             // PRISMA counts studies and reports separately

    /// Proof that the full text is actually in hand — the file exists, really is a PDF, and
    /// opens. Cached, because this is asked once per row on every redraw.
    var pdfProof: PDFVault.Proof { PDFVault.proof(for: pdfPath) }

    /// Retrieved in the PRISMA sense: a readable full text is on disk. A `pdfURL` the record
    /// never downloaded does not count, and neither does a path whose file has gone.
    var hasPDF: Bool { pdfProof.retrieved }

    /// The record claims a file but it cannot be read — deleted, moved, or never a PDF.
    var pdfBroken: Bool { !pdfPath.isEmpty && !pdfProof.retrieved }

    var authorLine: String {
        if authors.isEmpty { return "Unknown author" }
        if authors.count <= 3 { return authors.joined(separator: ", ") }
        return "\(authors[0]) et al."
    }

    var citeKey: String {
        let last = (authors.first ?? "anon")
            .split(separator: " ").last.map(String.init) ?? "anon"
        let clean = last.lowercased().filter { $0.isLetter }
        return "\(clean.isEmpty ? "anon" : clean)\(year.map(String.init) ?? "nd")"
    }

    /// APA-ish reference line used in exports and evidence cards.
    var reference: String {
        var s = authorLine
        if let y = year { s += " (\(y))." } else { s += " (n.d.)." }
        s += " \(title)."
        if !venue.isEmpty { s += " \(venue)." }
        if !doi.isEmpty { s += " https://doi.org/\(doi)" }
        return s
    }
}

// MARK: - Tag

/// A user-defined information category. Colour is the whole point: the colour you
/// highlight with in the reader IS the category the evidence lands in.
struct Tag: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var name: String
    var colorHex: String
    var kind: String = TagKind.type.rawValue
    var detail: String = ""           // definition / coding rule for this tag
    var sortOrder: Int = 0
    var shortcut: String = ""         // 1–9, pressed in the reader to highlight in this colour

    /// Adaptive so the same tag reads on a white page and a dark one.
    var color: Color { .readable(colorHex) }
    /// The literal colour, for the PDF highlight itself and for exports.
    var rawColor: Color { Color(hex: colorHex) }
    var tagKind: TagKind { TagKind(rawValue: kind) ?? .type }
}

/// Not every tag means the same kind of thing. "Interview" describes what a passage IS;
/// "Trust" describes what it is ABOUT; "Needs checking" describes its state. Keeping these
/// on separate axes is what lets you filter to "all Findings about Trust that are Verified".
enum TagKind: String, CaseIterable, Identifiable {
    case type, theme, status, datatype, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .type: return "Type"
        case .theme: return "Theme"
        case .status: return "Status"
        case .datatype: return "Data type"
        case .custom: return "Custom"
        }
    }

    var blurb: String {
        switch self {
        case .type: return "What the passage is — a method, a finding, a limitation. These are the colours you highlight with."
        case .theme: return "What the passage is about — the ideas you are tracing across the corpus."
        case .status: return "Where it stands in your own process — important, needs reading, resolved."
        case .datatype: return "What kind of data it came from — qualitative, quantitative, mixed."
        case .custom: return "Your own axis."
        }
    }

    var icon: String {
        switch self {
        case .type: return "square.on.circle"
        case .theme: return "lightbulb"
        case .status: return "flag"
        case .datatype: return "chart.bar"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Evidence (a highlight, or a manually typed note)

struct Evidence: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var paperId: Int
    var page: Int = 0                 // 0-based PDF page index; -1 for evidence with no page
    var quote: String = ""
    var note: String = ""
    var colorHex: String = Palette.yellowHex
    var tagIds: [Int] = []
    var rects: [CGRect] = []          // selection rects in PDF page space, for re-drawing
    var createdAt: Date = Date()
    var aiGenerated: Bool = false
    var kind: EvidenceKind = .quote
    var stance: Stance = .evidence
    var confidence: Confidence = .medium
    var verification: Verification = .unchecked

    var hasLocation: Bool { page >= 0 && !rects.isEmpty }
}

// MARK: - Literature review matrix

struct MatrixColumn: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var name: String
    var prompt: String = ""           // what you're asking of each paper — also the AI extraction prompt
    var sortOrder: Int = 0
    var width: Double = 220
}

struct MatrixCell: Hashable {
    var paperId: Int
    var columnId: Int
    var value: String = ""
    var evidenceIds: [Int] = []       // cells cite the highlights they came from
    var aiGenerated: Bool = false
}

// MARK: - Search results (pre-import)

struct SearchHit: Identifiable, Hashable {
    var id: String                    // provider-native id
    var title: String
    var authors: [String]
    var year: Int?
    var venue: String
    var doi: String
    var abstract: String
    var url: String
    var pdfURL: String
    var provider: String
    var oaStatus: String
    var citedBy: Int
    var mergedFrom: [String] = []     // providers that also returned this record
    var sdgs: [String] = []
    var pubDate: String = ""
    var docType: String = ""
    var language: String = ""
    var openAlexId: String = ""
    var references: [String] = []

    var dedupeKey: String { Dedupe.key(doi: doi, title: title, year: year) }
}

// MARK: - Deduplication

/// Deciding whether two records are the same paper. DOI is definitive. Otherwise the
/// normalised title carries it: the same article is routinely dated a year apart across
/// databases because of online-first publication, so the year only joins the key when
/// the title is too short to identify a paper on its own.
enum Dedupe {
    static func key(doi: String, title: String, year: Int?) -> String {
        let d = doi.trimmingCharacters(in: .whitespaces).lowercased()
        if !d.isEmpty { return "doi:" + d }
        let t = title.lowercased().filter { $0.isLetter || $0.isNumber }
        if t.count >= 25 { return "t:" + String(t.prefix(90)) }
        return "t:" + t + ":" + (year.map(String.init) ?? "")
    }
}

// MARK: - Colour palette

enum Palette {
    static let yellowHex  = "#F2C14E"
    static let greenHex   = "#4CAF7D"
    static let blueHex    = "#4C8DF2"
    static let pinkHex    = "#E86A9A"
    static let purpleHex  = "#9B6BE8"
    static let orangeHex  = "#EF8A45"
    static let tealHex    = "#3FB8AF"
    static let redHex     = "#E2564D"

    static let highlightHexes = [yellowHex, greenHex, blueHex, pinkHex, purpleHex, orangeHex, tealHex, redHex]

    static let emerald = Color.readable(greenHex)
    static let amber   = Color.readable(yellowHex)
    static let rose    = Color.readable(redHex)
    static let violet  = Color.readable(purpleHex)
    static let slate   = Color.readable("#8A93A3")
    static let accent  = Color.readable(blueHex)
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        } else { r = 0.5; g = 0.5; b = 0.5 }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}
