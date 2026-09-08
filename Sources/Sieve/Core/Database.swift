import Foundation

/// Schema owner. Everything lives in one SQLite file inside the library folder,
/// so a whole review is a single portable directory you can back up or hand over.
enum Schema {
    static func migrate(_ db: SQLiteDB) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

        CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            question TEXT NOT NULL DEFAULT '',
            inclusion TEXT NOT NULL DEFAULT '',
            exclusion TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS papers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            title TEXT NOT NULL DEFAULT '',
            authors TEXT NOT NULL DEFAULT '',
            year INTEGER,
            venue TEXT NOT NULL DEFAULT '',
            doi TEXT NOT NULL DEFAULT '',
            abstract TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            pdf_url TEXT NOT NULL DEFAULT '',
            pdf_path TEXT NOT NULL DEFAULT '',
            source_db TEXT NOT NULL DEFAULT '',
            source_query TEXT NOT NULL DEFAULT '',
            oa_status TEXT NOT NULL DEFAULT '',
            cited_by INTEGER NOT NULL DEFAULT 0,
            added_at REAL NOT NULL,
            accessed_at REAL,
            stage TEXT NOT NULL DEFAULT 'identified',
            exclude_reason TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            starred INTEGER NOT NULL DEFAULT 0,
            dedupe_key TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_papers_project ON papers(project_id);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_papers_dedupe ON papers(project_id, dedupe_key);

        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            color TEXT NOT NULL DEFAULT '#8A93A3',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_folders_project ON folders(project_id);

        -- A paper can sit in several collections at once, the way it can in Zotero. The
        -- collection is a label on the record, never a location: nothing is moved on disk
        -- when you file a paper, and removing it from a collection never deletes anything.
        CREATE TABLE IF NOT EXISTS paper_folders (
            paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
            folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
            added_at REAL NOT NULL DEFAULT 0,
            PRIMARY KEY (paper_id, folder_id)
        );
        CREATE INDEX IF NOT EXISTS idx_pf_folder ON paper_folders(folder_id);

        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'category',
            detail TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            shortcut TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_tags_project ON tags(project_id);

        CREATE TABLE IF NOT EXISTS evidence (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
            page INTEGER NOT NULL DEFAULT -1,
            quote TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            color TEXT NOT NULL DEFAULT '',
            rects TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL,
            ai_generated INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_evidence_paper ON evidence(paper_id);

        CREATE TABLE IF NOT EXISTS evidence_tags (
            evidence_id INTEGER NOT NULL REFERENCES evidence(id) ON DELETE CASCADE,
            tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (evidence_id, tag_id)
        );

        CREATE TABLE IF NOT EXISTS matrix_columns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            prompt TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            width REAL NOT NULL DEFAULT 220
        );

        CREATE TABLE IF NOT EXISTS matrix_cells (
            paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
            column_id INTEGER NOT NULL REFERENCES matrix_columns(id) ON DELETE CASCADE,
            value TEXT NOT NULL DEFAULT '',
            evidence_ids TEXT NOT NULL DEFAULT '',
            ai_generated INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (paper_id, column_id)
        );

        CREATE TABLE IF NOT EXISTS relations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            from_kind TEXT NOT NULL,
            from_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            to_kind TEXT NOT NULL,
            to_id INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_rel_from ON relations(project_id, from_kind, from_id);
        CREATE INDEX IF NOT EXISTS idx_rel_to ON relations(project_id, to_kind, to_id);

        CREATE TABLE IF NOT EXISTS methods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            blocks TEXT NOT NULL DEFAULT '',
            is_template INTEGER NOT NULL DEFAULT 0,
            current_step INTEGER NOT NULL DEFAULT 0
        );

        -- Counts PRISMA requires that cannot be derived from screening decisions:
        -- registers vs databases, automation-tool exclusions, other-methods sources,
        -- and the previous-version studies an updated review carries forward.
        CREATE TABLE IF NOT EXISTS prisma_counts (
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            key TEXT NOT NULL,
            value INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (project_id, key)
        );

        -- The 27-item PRISMA 2020 reporting checklist, tracked per review.
        CREATE TABLE IF NOT EXISTS checklist (
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            item TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'todo',
            location TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (project_id, item)
        );

        -- Append-only record of everything the assistant was asked and everything it said,
        -- and what the human did about it afterwards. A boolean "this was AI" is enough to
        -- put a badge on screen; it is not enough to answer "what did the model claim, and
        -- did anyone check it?" — which is the question a supervisor, a reviewer or a journal
        -- will actually ask.
        CREATE TABLE IF NOT EXISTS ai_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            at REAL NOT NULL,
            kind TEXT NOT NULL,
            model TEXT NOT NULL DEFAULT '',
            subject_kind TEXT NOT NULL DEFAULT '',
            subject_id INTEGER NOT NULL DEFAULT 0,
            column_id INTEGER NOT NULL DEFAULT 0,
            asked TEXT NOT NULL DEFAULT '',
            said TEXT NOT NULL DEFAULT '',
            confidence TEXT NOT NULL DEFAULT '',
            outcome TEXT NOT NULL DEFAULT 'pending',
            outcome_at REAL,
            human_note TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_ai_project ON ai_events(project_id, outcome);
        CREATE INDEX IF NOT EXISTS idx_ai_subject ON ai_events(subject_kind, subject_id);

        CREATE TABLE IF NOT EXISTS search_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            query TEXT NOT NULL,
            providers TEXT NOT NULL DEFAULT '',
            n_results INTEGER NOT NULL DEFAULT 0,
            n_imported INTEGER NOT NULL DEFAULT 0,
            run_at REAL NOT NULL
        );
        """)

        // Added after the first release. SQLite has no "ADD COLUMN IF NOT EXISTS",
        // so each one is attempted and a duplicate-column error is the success case.
        let later: [(String, String, String)] = [
            ("papers", "folder_id", "INTEGER"),
            ("papers", "conclusion", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "to_read", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "sdgs", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "pub_date", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "doc_type", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "language", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "openalex_id", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "refs", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "source_type", "TEXT NOT NULL DEFAULT 'paper'"),
            ("papers", "keywords", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "extracted_conclusion", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "conclusion_heading", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "report_count", "INTEGER NOT NULL DEFAULT 1"),
            ("evidence", "kind", "TEXT NOT NULL DEFAULT 'quote'"),
            ("evidence", "stance", "TEXT NOT NULL DEFAULT 'evidence'"),
            ("evidence", "confidence", "TEXT NOT NULL DEFAULT 'medium'"),
            ("evidence", "verification", "TEXT NOT NULL DEFAULT 'unchecked'"),
            // A smart collection has a rule instead of members; it fills itself.
            ("folders", "rule", "TEXT NOT NULL DEFAULT ''"),
            ("folders", "icon", "TEXT NOT NULL DEFAULT ''"),
            ("papers", "file_hash", "TEXT NOT NULL DEFAULT ''"),
        ]
        for (table, column, type) in later {
            try? db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(type);")
        }

        // Tags used to have one axis called "category"; it is now the "type" axis, sitting
        // alongside theme, status and data type.
        try? db.execute("UPDATE tags SET kind='type' WHERE kind='category';")

        // Folders used to be a single column on the paper, so a paper could only be in one.
        // Carry those memberships into the join table that replaces it.
        try? db.execute("""
            INSERT OR IGNORE INTO paper_folders (paper_id, folder_id, added_at)
            SELECT id, folder_id, added_at FROM papers WHERE folder_id IS NOT NULL;
            """)
    }

    /// Categories every new review starts with. They're only defaults — the point of
    /// the app is that you rename, recolour, delete and add your own.
    static let defaultTags: [(String, String, String, String)] = [
        // name, colour, kind, coding rule
        ("Definition",   Palette.blueHex,   "type", "How the source defines a key construct."),
        ("Method",       Palette.purpleHex, "type", "Study design, sample, instrument, procedure."),
        ("Finding",      Palette.greenHex,  "type", "A result the authors actually report."),
        ("Limitation",   Palette.orangeHex, "type", "Weakness the authors admit, or one you spot."),
        ("Gap",          Palette.pinkHex,   "type", "Something unstudied — your opening."),
        ("Contradiction",Palette.redHex,    "type", "Conflicts with another source in the corpus."),
        ("Quote",        Palette.yellowHex, "type", "Verbatim line worth quoting in the write-up."),
        ("Theory",       Palette.tealHex,   "type", "Theoretical frame or model invoked."),
        ("Important",    "#E2564D",         "status", "Comes back into the argument."),
        ("Needs reading","#EF8A45",         "status", "Flagged to come back to."),
        ("Resolved",     "#4CAF7D",         "status", "Dealt with — no longer open."),
        ("Qualitative",  "#7C8AA3",         "datatype", "Interviews, ethnography, open text."),
        ("Quantitative", "#5F7A8C",         "datatype", "Numbers, statistics, measured effects."),
        ("Mixed methods","#6E7F92",         "datatype", "Both, combined by design."),
    ]

    static let defaultColumns: [(String, String)] = [
        ("Research question", "What question does this paper set out to answer?"),
        ("Method",            "Design, sample size, participants, instruments."),
        ("Key findings",      "The main results, in the authors' own terms."),
        ("Theory / framework","Which theory or model frames the work?"),
        ("Limitations",       "What the study cannot claim."),
        ("Relevance to me",   "Why this paper matters for my review question."),
    ]
}

// MARK: - PRISMA 2020

/// The counts PRISMA 2020 asks for that no amount of screening can infer: how many records
/// came from registers rather than databases, how many an automation tool removed, what an
/// updated review carries forward from its previous version. Taken from the official flow
/// diagram templates (Page MJ et al., BMJ 2021;372:n71).
enum PrismaKey {
    static let registers = "registers"                       // records identified from registers
    static let automationRemoved = "automation_removed"      // marked ineligible by automation, pre-screening
    static let otherRemoved = "other_removed"                // removed before screening for other reasons
    static let automationExcluded = "automation_excluded"    // excluded at screening by automation
    static let websites = "other_websites"
    static let organisations = "other_organisations"
    static let citationSearching = "other_citation"
    static let otherSought = "other_sought"
    static let otherNotRetrieved = "other_not_retrieved"
    static let otherAssessed = "other_assessed"
    static let otherExcluded = "other_excluded"
    static let otherIncluded = "other_included"
    static let previousStudies = "previous_studies"          // updated reviews only
    static let previousReports = "previous_reports"

    static let all = [registers, automationRemoved, otherRemoved, automationExcluded,
                      websites, organisations, citationSearching, otherSought,
                      otherNotRetrieved, otherAssessed, otherExcluded, otherIncluded,
                      previousStudies, previousReports]
}

/// The boxes on the flow diagram whose numbers can be clicked through to the records.
enum PrismaBox: String, CaseIterable, Identifiable {
    case identified, removedBefore, screened, excludedScreen, sought, notRetrieved,
         assessed, excludedFull, included
    var id: String { rawValue }
}

/// Which of the four official PRISMA 2020 flow diagrams this review reports with.
enum PrismaVariant: String, CaseIterable, Identifiable {
    case newV1, newV2, updatedV1, updatedV2
    var id: String { rawValue }

    var label: String {
        switch self {
        case .newV1: return "New review — databases & registers"
        case .newV2: return "New review — including other methods"
        case .updatedV1: return "Updated review — databases & registers"
        case .updatedV2: return "Updated review — including other methods"
        }
    }

    var blurb: String {
        switch self {
        case .newV1: return "The standard diagram. Use it when every record came from a database or register."
        case .newV2: return "Adds a second column for records found through websites, organisations and citation searching."
        case .updatedV1: return "For a review that updates a previous version — carries its included studies forward."
        case .updatedV2: return "An update that also searched websites, organisations and reference lists."
        }
    }

    var isUpdated: Bool { self == .updatedV1 || self == .updatedV2 }
    var hasOtherMethods: Bool { self == .newV2 || self == .updatedV2 }
}

/// The PRISMA 2020 reporting checklist, verbatim from the official document.
struct ChecklistItem: Identifiable, Hashable {
    let id: String          // item number, e.g. "10a"
    let section: String
    let topic: String
    let text: String
}

enum PrismaChecklist {
    static let items: [ChecklistItem] = [
        .init(id: "1", section: "Title", topic: "Title", text: "Identify the report as a systematic review."),
        .init(id: "2", section: "Abstract", topic: "Abstract", text: "See the PRISMA 2020 for Abstracts checklist."),
        .init(id: "3", section: "Introduction", topic: "Rationale", text: "Describe the rationale for the review in the context of existing knowledge."),
        .init(id: "4", section: "Introduction", topic: "Objectives", text: "Provide an explicit statement of the objective(s) or question(s) the review addresses."),
        .init(id: "5", section: "Methods", topic: "Eligibility criteria", text: "Specify the inclusion and exclusion criteria for the review and how studies were grouped for the syntheses."),
        .init(id: "6", section: "Methods", topic: "Information sources", text: "Specify all databases, registers, websites, organisations, reference lists and other sources searched or consulted to identify studies. Specify the date when each source was last searched or consulted."),
        .init(id: "7", section: "Methods", topic: "Search strategy", text: "Present the full search strategies for all databases, registers and websites, including any filters and limits used."),
        .init(id: "8", section: "Methods", topic: "Selection process", text: "Specify the methods used to decide whether a study met the inclusion criteria of the review, including how many reviewers screened each record and each report retrieved, whether they worked independently, and if applicable, details of automation tools used in the process."),
        .init(id: "9", section: "Methods", topic: "Data collection process", text: "Specify the methods used to collect data from reports, including how many reviewers collected data from each report, whether they worked independently, any processes for obtaining or confirming data from study investigators, and if applicable, details of automation tools used in the process."),
        .init(id: "10a", section: "Methods", topic: "Data items", text: "List and define all outcomes for which data were sought. Specify whether all results that were compatible with each outcome domain in each study were sought, and if not, the methods used to decide which results to collect."),
        .init(id: "10b", section: "Methods", topic: "Data items", text: "List and define all other variables for which data were sought (e.g. participant and intervention characteristics, funding sources). Describe any assumptions made about any missing or unclear information."),
        .init(id: "11", section: "Methods", topic: "Study risk of bias assessment", text: "Specify the methods used to assess risk of bias in the included studies, including details of the tool(s) used, how many reviewers assessed each study and whether they worked independently, and if applicable, details of automation tools used in the process."),
        .init(id: "12", section: "Methods", topic: "Effect measures", text: "Specify for each outcome the effect measure(s) (e.g. risk ratio, mean difference) used in the synthesis or presentation of results."),
        .init(id: "13a", section: "Methods", topic: "Synthesis methods", text: "Describe the processes used to decide which studies were eligible for each synthesis."),
        .init(id: "13b", section: "Methods", topic: "Synthesis methods", text: "Describe any methods required to prepare the data for presentation or synthesis, such as handling of missing summary statistics, or data conversions."),
        .init(id: "13c", section: "Methods", topic: "Synthesis methods", text: "Describe any methods used to tabulate or visually display results of individual studies and syntheses."),
        .init(id: "13d", section: "Methods", topic: "Synthesis methods", text: "Describe any methods used to synthesize results and provide a rationale for the choice(s). If meta-analysis was performed, describe the model(s), method(s) to identify the presence and extent of statistical heterogeneity, and software package(s) used."),
        .init(id: "13e", section: "Methods", topic: "Synthesis methods", text: "Describe any methods used to explore possible causes of heterogeneity among study results (e.g. subgroup analysis, meta-regression)."),
        .init(id: "13f", section: "Methods", topic: "Synthesis methods", text: "Describe any sensitivity analyses conducted to assess robustness of the synthesized results."),
        .init(id: "14", section: "Methods", topic: "Reporting bias assessment", text: "Describe any methods used to assess risk of bias due to missing results in a synthesis (arising from reporting biases)."),
        .init(id: "15", section: "Methods", topic: "Certainty assessment", text: "Describe any methods used to assess certainty (or confidence) in the body of evidence for an outcome."),
        .init(id: "16a", section: "Results", topic: "Study selection", text: "Describe the results of the search and selection process, from the number of records identified in the search to the number of studies included in the review, ideally using a flow diagram."),
        .init(id: "16b", section: "Results", topic: "Study selection", text: "Cite studies that might appear to meet the inclusion criteria, but which were excluded, and explain why they were excluded."),
        .init(id: "17", section: "Results", topic: "Study characteristics", text: "Cite each included study and present its characteristics."),
        .init(id: "18", section: "Results", topic: "Risk of bias in studies", text: "Present assessments of risk of bias for each included study."),
        .init(id: "19", section: "Results", topic: "Results of individual studies", text: "For all outcomes, present, for each study: (a) summary statistics for each group and (b) an effect estimate and its precision, ideally using structured tables or plots."),
        .init(id: "20a", section: "Results", topic: "Results of syntheses", text: "For each synthesis, briefly summarise the characteristics and risk of bias among contributing studies."),
        .init(id: "20b", section: "Results", topic: "Results of syntheses", text: "Present results of all statistical syntheses conducted. If meta-analysis was done, present for each the summary estimate and its precision and measures of statistical heterogeneity."),
        .init(id: "20c", section: "Results", topic: "Results of syntheses", text: "Present results of all investigations of possible causes of heterogeneity among study results."),
        .init(id: "20d", section: "Results", topic: "Results of syntheses", text: "Present results of all sensitivity analyses conducted to assess the robustness of the synthesized results."),
        .init(id: "21", section: "Results", topic: "Reporting biases", text: "Present assessments of risk of bias due to missing results (arising from reporting biases) for each synthesis assessed."),
        .init(id: "22", section: "Results", topic: "Certainty of evidence", text: "Present assessments of certainty (or confidence) in the body of evidence for each outcome assessed."),
        .init(id: "23a", section: "Discussion", topic: "Discussion", text: "Provide a general interpretation of the results in the context of other evidence."),
        .init(id: "23b", section: "Discussion", topic: "Discussion", text: "Discuss any limitations of the evidence included in the review."),
        .init(id: "23c", section: "Discussion", topic: "Discussion", text: "Discuss any limitations of the review processes used."),
        .init(id: "23d", section: "Discussion", topic: "Discussion", text: "Discuss implications of the results for practice, policy, and future research."),
        .init(id: "24a", section: "Other information", topic: "Registration and protocol", text: "Provide registration information for the review, including register name and registration number, or state that the review was not registered."),
        .init(id: "24b", section: "Other information", topic: "Registration and protocol", text: "Indicate where the review protocol can be accessed, or state that a protocol was not prepared."),
        .init(id: "24c", section: "Other information", topic: "Registration and protocol", text: "Describe and explain any amendments to information provided at registration or in the protocol."),
        .init(id: "25", section: "Other information", topic: "Support", text: "Describe sources of financial or non-financial support for the review, and the role of the funders or sponsors in the review."),
        .init(id: "26", section: "Other information", topic: "Competing interests", text: "Declare any competing interests of review authors."),
        .init(id: "27", section: "Other information", topic: "Availability of data, code and other materials", text: "Report which of the following are publicly available and where they can be found: template data collection forms; data extracted from included studies; data used for all analyses; analytic code; any other materials used in the review."),
    ]

    static let citation = "Page MJ, McKenzie JE, Bossuyt PM, Boutron I, Hoffmann TC, Mulrow CD, et al. The PRISMA 2020 statement: an updated guideline for reporting systematic reviews. BMJ 2021;372:n71. doi:10.1136/bmj.n71"
    static let elaboration = "https://www.bmj.com/content/372/bmj.n160"
    static let statement = "https://www.bmj.com/content/372/bmj.n71"
}

/// Where everything lives on disk.
///
/// Two things are separated deliberately:
///
/// **Physical layout** — each review owns a directory, so one review's PDFs are never mixed
/// with another's and a whole review can be zipped, moved or handed over on its own.
///
/// **Stored paths** — a paper records where its PDF sits *relative to the library root*, so
/// moving the library to an external drive or iCloud does not break every record in it.
enum Library {
    private static let locationKey = "sieve.libraryRoot"

    /// The library root. Defaults to ~/Documents/Sieve; the user can put it anywhere.
    static var root: URL {
        if let saved = UserDefaults.standard.string(forKey: locationKey), !saved.isEmpty {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sieve", isDirectory: true)
    }

    static var isCustomLocation: Bool {
        !(UserDefaults.standard.string(forKey: locationKey) ?? "").isEmpty
    }

    static func setRoot(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: locationKey)
    }

    static func resetRoot() {
        UserDefaults.standard.removeObject(forKey: locationKey)
    }

    static var databaseURL: URL { root.appendingPathComponent("sieve.sqlite") }
    static var reviewsDir: URL { root.appendingPathComponent("Reviews", isDirectory: true) }
    static var exportDir: URL { root.appendingPathComponent("Exports", isDirectory: true) }

    /// The shared folder used before reviews had their own. Kept so old records resolve.
    static var legacyPDFDir: URL { root.appendingPathComponent("PDFs", isDirectory: true) }
    static var pdfDir: URL { legacyPDFDir }

    /// A review's own directory, named so it is recognisable in Finder but stable under
    /// renaming — the id is what actually identifies it.
    static func reviewDir(id: Int, name: String) -> URL {
        let slug = name
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " +", with: "-", options: .regularExpression)
            .lowercased()
        let stem = slug.isEmpty ? "review" : String(slug.prefix(50))
        return reviewsDir.appendingPathComponent("\(stem)-\(id)", isDirectory: true)
    }

    static func pdfDir(id: Int, name: String) -> URL {
        reviewDir(id: id, name: name).appendingPathComponent("PDFs", isDirectory: true)
    }

    // MARK: Relative paths

    /// Turns an absolute path inside the library into one stored relative to the root.
    /// Files outside the library keep their absolute path — someone may deliberately point
    /// at a PDF that lives elsewhere.
    static func relative(_ absolute: String) -> String {
        guard !absolute.isEmpty else { return "" }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard absolute.hasPrefix(rootPath) else { return absolute }
        return String(absolute.dropFirst(rootPath.count))
    }

    /// Resolves a stored path back to somewhere on disk.
    static func absolute(_ stored: String) -> String {
        guard !stored.isEmpty else { return "" }
        if stored.hasPrefix("/") { return stored }
        return root.appendingPathComponent(stored).path
    }

    static func prepare() throws {
        for dir in [root, reviewsDir, exportDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func prepare(reviewId: Int, name: String) throws {
        try FileManager.default.createDirectory(at: pdfDir(id: reviewId, name: name),
                                                withIntermediateDirectories: true)
    }

    /// A short content fingerprint, used so the same PDF is never stored twice.
    static func fingerprint(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) as? Int ?? 0
        // The first 256 KB plus the byte count identifies a PDF well enough to catch a
        // re-drop of the same file, without reading a 50 MB document to find out.
        let head = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        guard !head.isEmpty else { return nil }
        var hash: UInt64 = 1469598103934665603
        for byte in head {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return String(format: "%016llx-%d", hash, size)
    }
}
