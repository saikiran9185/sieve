import Foundation
import SwiftUI

/// Single source of truth. Views observe this; nothing else touches SQL.
@MainActor
final class Store: ObservableObject {
    let db: SQLiteDB

    @Published var projects: [Project] = []
    @Published var currentProjectId: Int = 0
    @Published var papers: [Paper] = []
    @Published var folders: [Folder] = []
    @Published var relations: [Relation] = []
    @Published var membership: [Int: Set<Int>] = [:]
    @Published var aiEvents: [AIEvent] = []
    @Published var frames: [Frame] = []
    @Published var frameAxes: [Int: [FrameAxis]] = [:]      // frame id → its rows and columns
    @Published var frameCells: [String: FrameCell] = [:]    // "frame-row-col"
    @Published var methods: [Method] = []
    @Published var prismaCounts: [String: Int] = [:]
    @Published var checklist: [String: (state: String, location: String)] = [:]
    @Published var tags: [Tag] = []
    @Published var columns: [MatrixColumn] = []
    @Published var evidence: [Evidence] = []
    @Published var cells: [String: MatrixCell] = [:]   // "paperId-columnId"
    @Published var lastError: String?
    @Published var toast: String?

    var project: Project? { projects.first { $0.id == currentProjectId } }
    /// The colours you highlight with: the "type" axis.
    var categoryTags: [Tag] { tags.filter { $0.tagKind == .type } }
    var dataTypeTags: [Tag] { tags.filter { $0.tagKind == .datatype } }
    var themeTags: [Tag] { tags.filter { $0.tagKind == .theme } }
    var statusTags: [Tag] { tags.filter { $0.tagKind == .status } }

    init() {
        do {
            try Library.prepare()
            db = try SQLiteDB(path: Library.databaseURL.path)
            try Schema.migrate(db)
        } catch {
            // A dead database is unrecoverable; surface it loudly rather than limping on.
            fatalError("Sieve could not open its library: \(error)")
        }
        reloadProjects()
        if projects.isEmpty {
            _ = createProject(name: "My first review")
        }
        currentProjectId = projects.first?.id ?? 0
        // Existing libraries predate the method templates, so seed them on launch rather
        // than only when a review is created.
        seedMethodTemplatesIfNeeded()
        reloadAll()
    }

    private func fail(_ error: Error, _ what: String) {
        lastError = "\(what): \(error.localizedDescription)"
    }

    func flash(_ message: String) {
        toast = message
        Task { try? await Task.sleep(nanoseconds: 2_600_000_000); if toast == message { toast = nil } }
    }

    // MARK: - Projects

    func reloadProjects() {
        do {
            projects = try db.query("SELECT * FROM projects ORDER BY created_at DESC").map {
                Project(id: $0.int("id") ?? 0,
                        name: $0.string("name") ?? "",
                        question: $0.string("question") ?? "",
                        inclusionCriteria: $0.string("inclusion") ?? "",
                        exclusionCriteria: $0.string("exclusion") ?? "",
                        createdAt: $0.date("created_at") ?? Date())
            }
        } catch { fail(error, "Loading reviews") }
    }

    @discardableResult
    func createProject(name: String) -> Int {
        do {
            let id = try db.run("INSERT INTO projects (name, created_at) VALUES (?, ?)", [name, Date()])
            let pid = Int(id)
            for (i, t) in Schema.defaultTags.enumerated() {
                try db.run("""
                    INSERT INTO tags (project_id, name, color, kind, detail, sort_order, shortcut)
                    VALUES (?,?,?,?,?,?,?)
                    """, [pid, t.0, t.1, t.2, t.3, i, i < 9 && t.2 == "category" ? String(i + 1) : ""])
            }
            for (i, c) in Schema.defaultColumns.enumerated() {
                try db.run("INSERT INTO matrix_columns (project_id, name, prompt, sort_order) VALUES (?,?,?,?)",
                           [pid, c.0, c.1, i])
            }
            reloadProjects()
            seedMethodTemplatesIfNeeded()
            return pid
        } catch { fail(error, "Creating review"); return 0 }
    }

    /// Ships the standard methodologies as editable recipes. They are templates, not rails:
    /// adopting one copies its steps into the review, where they can be changed freely.
    func seedMethodTemplatesIfNeeded() {
        guard (try? db.query("SELECT id FROM methods WHERE is_template=1 LIMIT 1"))?.isEmpty ?? true else { return }
        let presets: [(String, String, [MethodBlock])] = [
            ("Systematic review (PRISMA)",
             "The full PRISMA 2020 process: a documented search, two-stage screening with recorded reasons, structured extraction and a flow diagram.",
             [.search, .importSources, .screen, .retrieve, .screen, .extract, .synthesize, .export]),
            ("Scoping review",
             "Maps what exists on a topic rather than answering a narrow question. Charting replaces extraction; no risk-of-bias step.",
             [.search, .importSources, .screen, .retrieve, .extract, .cluster, .synthesize, .export]),
            ("Literature review",
             "The ordinary reading-and-writing review: gather, read, code, and build the argument.",
             [.search, .importSources, .read, .highlight, .code, .synthesize, .export]),
            ("Thematic analysis",
             "Braun & Clarke's six phases: familiarise, code, search for themes, review, define, write up.",
             [.importSources, .read, .highlight, .code, .cluster, .relate, .validate, .synthesize]),
            ("Grounded theory",
             "Open coding, then constant comparison and memoing until categories are saturated.",
             [.importSources, .read, .code, .memo, .compare, .cluster, .relate, .synthesize]),
            ("Content analysis",
             "A fixed coding frame applied consistently, then counted.",
             [.tag, .importSources, .read, .code, .extract, .compare, .export]),
            ("Comparative analysis",
             "Set cases side by side on the same dimensions and read across them.",
             [.importSources, .read, .extract, .compare, .rank, .synthesize, .export]),
            ("Just reading",
             "Three steps. Open a paper, mark what matters, write a note.",
             [.read, .highlight, .memo]),
            ("UX research study",
             "Interviews and sessions rather than papers: collect, transcribe, code what people said, cluster it, and lay it into a journey or empathy map that cites the quotes.",
             [.importSources, .read, .highlight, .code, .cluster, .frame, .synthesize, .export]),
            ("Design research — discover",
             "The front half of a design project: find out what is true before deciding anything. Ends in a framing you can defend.",
             [.search, .importSources, .read, .highlight, .code, .frame, .validate, .synthesize]),
            ("Competitive and positioning",
             "Look at what already exists, compare it on the same dimensions, and work out where the gap is.",
             [.search, .importSources, .read, .highlight, .compare, .frame, .synthesize, .export]),
        ]
        for (name, detail, blocks) in presets {
            saveMethod(Method(id: 0, projectId: nil, name: name, detail: detail,
                              blocks: blocks, isTemplate: true))
        }
    }

    func updateProject(_ p: Project) {
        let oldName = projects.first { $0.id == p.id }?.name
        do {
            try db.run("UPDATE projects SET name=?, question=?, inclusion=?, exclusion=? WHERE id=?",
                       [p.name, p.question, p.inclusionCriteria, p.exclusionCriteria, p.id])
            reloadProjects()
            // The folder is named after the review, so renaming one renames the other.
            // Paths are stored relative to the library root, so nothing has to be rewritten.
            if let oldName, oldName != p.name {
                let from = Library.reviewDir(id: p.id, name: oldName)
                let to = Library.reviewDir(id: p.id, name: p.name)
                if from.path != to.path, FileManager.default.fileExists(atPath: from.path) {
                    do {
                        try FileManager.default.moveItem(at: from, to: to)
                        // Stored paths are relative and contain the folder name, so they have
                        // to follow it. Without this every PDF in the review would be lost
                        // the moment it was renamed.
                        let oldPrefix = Library.relative(from.path) + "/"
                        let newPrefix = Library.relative(to.path) + "/"
                        try db.run("""
                            UPDATE papers SET pdf_path = ? || substr(pdf_path, ?)
                            WHERE project_id = ? AND pdf_path LIKE ? || '%'
                            """, [newPrefix, oldPrefix.count + 1, p.id, oldPrefix])
                        PDFVault.invalidateAll()
                        reloadPapers()
                    } catch { fail(error, "Renaming the review folder") }
                }
            }
        } catch { fail(error, "Saving review") }
    }

    func deleteProject(_ id: Int) {
        do {
            try db.run("DELETE FROM projects WHERE id=?", [id])
            reloadProjects()
            if currentProjectId == id { currentProjectId = projects.first?.id ?? 0; reloadAll() }
        } catch { fail(error, "Deleting review") }
    }

    func switchTo(_ id: Int) { currentProjectId = id; reloadAll() }

    func reloadAll() {
        reloadTags(); reloadFolders(); reloadPapers(); reloadColumns(); reloadEvidence()
        reloadCells(); reloadRelations(); reloadMethods(); reloadPrismaCounts(); reloadChecklist()
        reloadMembership(); reloadAIEvents(); reloadFrames()
    }

    // MARK: - Papers

    /// Groups a run of changes so the papers table is read back once at the end instead of
    /// after every row. A bulk action over 60 records was rebuilding 8,940 row objects to
    /// change 60 of them, and the cost grows with the square of the review.
    private var suspendReloads = false

    func batch(_ body: () -> Void) {
        let wasSuspended = suspendReloads
        suspendReloads = true
        body()
        suspendReloads = wasSuspended
        guard !suspendReloads else { return }
        reloadPapers()
        reloadMembership()
    }

    func reloadPapers() {
        guard !suspendReloads else { return }
        do {
            papers = try db.query("SELECT * FROM papers WHERE project_id=? ORDER BY added_at DESC",
                                  [currentProjectId]).map(Store.paper(from:))
        } catch { fail(error, "Loading papers") }
    }

    static func paper(from r: SQLiteDB.Row) -> Paper {
        Paper(id: r.int("id") ?? 0,
              projectId: r.int("project_id") ?? 0,
              title: r.string("title") ?? "",
              authors: (r.string("authors") ?? "").split(separator: "\n").map(String.init),
              year: r.int("year"),
              venue: r.string("venue") ?? "",
              doi: r.string("doi") ?? "",
              abstract: r.string("abstract") ?? "",
              url: r.string("url") ?? "",
              pdfURL: r.string("pdf_url") ?? "",
              pdfPath: Library.absolute(r.string("pdf_path") ?? ""),
              sourceDB: r.string("source_db") ?? "",
              sourceQuery: r.string("source_query") ?? "",
              oaStatus: r.string("oa_status") ?? "",
              citedBy: r.int("cited_by") ?? 0,
              addedAt: r.date("added_at") ?? Date(),
              accessedAt: r.date("accessed_at"),
              stage: Stage(rawValue: r.string("stage") ?? "") ?? .identified,
              excludeReason: r.string("exclude_reason") ?? "",
              notes: r.string("notes") ?? "",
              starred: r.bool("starred"),
              dedupeKey: r.string("dedupe_key") ?? "",
              folderId: r.int("folder_id"),
              fileHash: r.string("file_hash") ?? "",
              conclusion: r.string("conclusion") ?? "",
              toRead: r.string("to_read") ?? "",
              sdgs: (r.string("sdgs") ?? "").split(separator: "|").map(String.init),
              pubDate: r.string("pub_date") ?? "",
              docType: r.string("doc_type") ?? "",
              language: r.string("language") ?? "",
              openAlexId: r.string("openalex_id") ?? "",
              references: (r.string("refs") ?? "").split(separator: " ").map(String.init),
              sourceType: SourceType(rawValue: r.string("source_type") ?? "") ?? .paper,
              keywords: (r.string("keywords") ?? "").split(separator: "|").map(String.init),
              extractedConclusion: r.string("extracted_conclusion") ?? "",
              conclusionHeading: r.string("conclusion_heading") ?? "",
              reportCount: r.int("report_count") ?? 1)
    }

    func paper(_ id: Int) -> Paper? { papers.first { $0.id == id } }

    /// Every paper in a review, whether or not it is the one on screen. The migration needs
    /// to walk all reviews, not only the open one.
    func papersRaw(projectId: Int) -> [Paper] {
        (try? db.query("SELECT * FROM papers WHERE project_id=?", [projectId]).map(Store.paper(from:))) ?? []
    }

    func clearPDFPath(_ paperId: Int) {
        do {
            try db.run("UPDATE papers SET pdf_path='' WHERE id=?", [paperId])
        } catch { fail(error, "Clearing a missing file") }
    }

    /// Insert a search hit. Returns nil when it is already in this review (dedupe by DOI, else title+year).
    @discardableResult
    func addPaper(from hit: SearchHit, query: String, folder: Int? = nil) -> Int? {
        do {
            let existing = try db.query("SELECT id FROM papers WHERE project_id=? AND dedupe_key=?",
                                        [currentProjectId, hit.dedupeKey])
            if !existing.isEmpty { return nil }
            let id = try db.run("""
                INSERT INTO papers (project_id, title, authors, year, venue, doi, abstract, url, pdf_url,
                                    source_db, source_query, oa_status, cited_by, added_at, stage, dedupe_key,
                                    folder_id, sdgs, pub_date, doc_type, language, openalex_id, refs)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, [currentProjectId, hit.title, hit.authors.joined(separator: "\n"), hit.year, hit.venue,
                      hit.doi, hit.abstract, hit.url, hit.pdfURL,
                      ([hit.provider] + hit.mergedFrom).joined(separator: " + "),
                      query, hit.oaStatus, hit.citedBy, Date(), Stage.identified.rawValue, hit.dedupeKey,
                      folder, hit.sdgs.joined(separator: "|"), hit.pubDate, hit.docType, hit.language,
                      hit.openAlexId, hit.references.joined(separator: " ")])
            return Int(id)
        } catch { fail(error, "Adding paper"); return nil }
    }

    @discardableResult
    func addManualPaper(title: String, authors: [String], year: Int?, venue: String, doi: String,
                        pdfPath: String, sourceDB: String, abstract: String = "", url: String = "") -> Int? {
        let key = Dedupe.key(doi: doi, title: title, year: year)
        do {
            if let dup = try db.query("SELECT id FROM papers WHERE project_id=? AND dedupe_key=?",
                                      [currentProjectId, key]).first {
                // Same record already here — just attach the PDF if it was missing one.
                let pid = dup.int("id") ?? 0
                if !pdfPath.isEmpty {
                    try db.run("UPDATE papers SET pdf_path=?, accessed_at=? WHERE id=?", [pdfPath, Date(), pid])
                    reloadPapers()
                }
                return nil
            }
            let id = try db.run("""
                INSERT INTO papers (project_id, title, authors, year, venue, doi, abstract, url, pdf_path,
                                    source_db, added_at, accessed_at, stage, dedupe_key)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, [currentProjectId, title, authors.joined(separator: "\n"), year, venue, doi, abstract, url,
                      pdfPath, sourceDB, Date(), pdfPath.isEmpty ? nil : Date(), Stage.identified.rawValue, key])
            reloadPapers()
            return Int(id)
        } catch { fail(error, "Adding paper"); return nil }
    }

    /// Creates a source that did not come from a database — an interview, a usability
    /// session, a field note, a competitor's website. UX research is mostly these, and until
    /// now the only way in was a literature search or a dropped PDF.
    @discardableResult
    func addSource(type: SourceType, title: String, participants: [String] = [],
                   date: Date? = nil, venue: String = "", url: String = "",
                   notes: String = "", stage: Stage = .included) -> Int? {
        let clean = title.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        // Own material is identified by title and date; it has no DOI to key on.
        let stamp = (date ?? Date()).formatted(.iso8601.year().month().day())
        let key = "own:" + type.rawValue + ":"
            + clean.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(60) + ":" + stamp
        do {
            if let existing = try db.query("SELECT id FROM papers WHERE project_id=? AND dedupe_key=?",
                                           [currentProjectId, key]).first {
                return existing.int("id")
            }
            let id = try db.run("""
                INSERT INTO papers (project_id, title, authors, year, venue, url, source_db,
                                    added_at, stage, dedupe_key, source_type, notes, pub_date, doc_type)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, [currentProjectId, clean, participants.joined(separator: "\n"),
                      Calendar.current.component(.year, from: date ?? Date()), venue, url,
                      "Collected by me", Date(), stage.rawValue, key, type.rawValue, notes,
                      stamp, type.label])
            reloadPapers()
            return Int(id)
        } catch { fail(error, "Adding the source"); return nil }
    }

    /// Sources you produced rather than found. These are what a UX study is made of.
    var ownSources: [Paper] {
        papers.filter { $0.sourceDB == "Collected by me" }
    }

    func updatePaper(_ p: Paper) {
        if let existing = paper(p.id), existing.pdfPath != p.pdfPath {
            PDFVault.invalidate(existing.pdfPath)
            PDFVault.invalidate(p.pdfPath)
        }
        do {
            try db.run("""
                UPDATE papers SET title=?, authors=?, year=?, venue=?, doi=?, abstract=?, url=?, pdf_url=?,
                                  pdf_path=?, stage=?, exclude_reason=?, notes=?, starred=?, accessed_at=?,
                                  folder_id=?, conclusion=?, to_read=?, sdgs=?, pub_date=?, doc_type=?,
                                  language=?, openalex_id=?, refs=?, source_type=?, keywords=?,
                                  extracted_conclusion=?, conclusion_heading=?, report_count=?,
                                  file_hash=?
                WHERE id=?
                """, [p.title, p.authors.joined(separator: "\n"), p.year, p.venue, p.doi, p.abstract, p.url,
                      p.pdfURL, Library.relative(p.pdfPath), p.stage.rawValue, p.excludeReason, p.notes, p.starred,
                      p.accessedAt, p.folderId, p.conclusion, p.toRead, p.sdgs.joined(separator: "|"),
                      p.pubDate, p.docType, p.language, p.openAlexId, p.references.joined(separator: " "),
                      p.sourceType.rawValue, p.keywords.joined(separator: "|"),
                      p.extractedConclusion, p.conclusionHeading, p.reportCount, p.fileHash,
                      p.id])
            reloadPapers()
        } catch { fail(error, "Saving paper") }
    }

    func setStage(_ paperId: Int, _ stage: Stage, reason: String = "") {
        do {
            try db.run("UPDATE papers SET stage=?, exclude_reason=? WHERE id=?", [stage.rawValue, reason, paperId])
            reloadPapers()
        } catch { fail(error, "Updating decision") }
    }

    func setPDFPath(_ paperId: Int, _ path: String) {
        do {
            if let old = paper(paperId)?.pdfPath { PDFVault.invalidate(old) }
            PDFVault.invalidate(path)
            try db.run("UPDATE papers SET pdf_path=?, accessed_at=? WHERE id=?",
                       [Library.relative(path), Date(), paperId])
            reloadPapers()
        } catch { fail(error, "Attaching PDF") }
    }

    func deletePaper(_ id: Int) {
        do {
            if let path = paper(id)?.pdfPath { PDFVault.invalidate(path) }
            try db.run("DELETE FROM papers WHERE id=?", [id])
            reloadPapers(); reloadEvidence()
        } catch { fail(error, "Deleting paper") }
    }

    func toggleStar(_ id: Int) {
        guard let p = paper(id) else { return }
        do { try db.run("UPDATE papers SET starred=? WHERE id=?", [!p.starred, id]); reloadPapers() }
        catch { fail(error, "Starring") }
    }

    /// Moves every record that was sought but never obtained into "not retrieved", so the
    /// stages match what is actually on disk.
    @discardableResult
    func markMissingAsNotRetrieved() -> Int {
        let targets = missingFullTexts.filter { $0.stage != .included }
        batch {
            for p in targets {
                setStage(p.id, .notRetrieved, reason: "Full text could not be obtained")
            }
        }
        return targets.count
    }

    /// Flags every record whose dedupe key collides with an earlier one. Runs across the
    /// whole project so imports from four databases collapse into one screening list.
    @discardableResult
    func markDuplicates() -> Int {
        var seen = Set<String>()
        var n = 0
        let sorted = papers.sorted { $0.addedAt < $1.addedAt }
        batch {
            for p in sorted where p.stage != .duplicate {
                if seen.contains(p.dedupeKey) {
                    setStage(p.id, .duplicate, reason: "Duplicate record")
                    n += 1
                } else { seen.insert(p.dedupeKey) }
            }
        }
        return n
    }

    // MARK: - Folders

    func reloadFolders() {
        do {
            folders = try db.query("SELECT * FROM folders WHERE project_id=? ORDER BY sort_order, name",
                                   [currentProjectId]).map {
                Folder(id: $0.int("id") ?? 0, projectId: $0.int("project_id") ?? 0,
                       parentId: $0.int("parent_id"), name: $0.string("name") ?? "",
                       colorHex: $0.string("color") ?? "#8A93A3", sortOrder: $0.int("sort_order") ?? 0,
                       rule: $0.string("rule") ?? "", icon: $0.string("icon") ?? "")
            }
        } catch { fail(error, "Loading folders") }
    }

    func folder(_ id: Int?) -> Folder? { id.flatMap { fid in folders.first { $0.id == fid } } }

    /// Which collections a paper belongs to. A paper can be in several at once.
    func collections(of paperId: Int) -> [Folder] {
        let ids = membership[paperId] ?? []
        return folders.filter { ids.contains($0.id) && !$0.isSmart }
    }

    func isIn(_ paperId: Int, folder id: Int) -> Bool {
        if let f = folder(id), let rule = f.smartRule {
            guard let p = paper(paperId) else { return false }
            let n = evidence.filter { $0.paperId == paperId }.count
            return rule.matches(p, evidenceCount: n)
        }
        return membership[paperId]?.contains(id) ?? false
    }

    func addToCollection(_ paperIds: [Int], _ folderId: Int) {
        guard let f = folder(folderId), !f.isSmart else {
            flash("That collection fills itself — its rule decides what is in it")
            return
        }
        do {
            for pid in paperIds {
                try db.run("INSERT OR IGNORE INTO paper_folders (paper_id, folder_id, added_at) VALUES (?,?,?)",
                           [pid, folderId, Date()])
            }
            reloadMembership()
        } catch { fail(error, "Filing papers") }
    }

    /// Removes the label only. The paper stays in the review and the file stays on disk.
    func removeFromCollection(_ paperIds: [Int], _ folderId: Int) {
        do {
            for pid in paperIds {
                try db.run("DELETE FROM paper_folders WHERE paper_id=? AND folder_id=?", [pid, folderId])
            }
            reloadMembership()
        } catch { fail(error, "Removing from collection") }
    }

    func reloadMembership() {
        do {
            var map: [Int: Set<Int>] = [:]
            for r in try db.query("""
                SELECT pf.paper_id AS p, pf.folder_id AS f FROM paper_folders pf
                JOIN papers pa ON pa.id = pf.paper_id WHERE pa.project_id=?
                """, [currentProjectId]) {
                map[r.int("p") ?? 0, default: []].insert(r.int("f") ?? 0)
            }
            membership = map
        } catch { fail(error, "Loading collections") }
    }

    func children(of parent: Int?) -> [Folder] {
        folders.filter { $0.parentId == parent }
    }

    /// Papers in a collection, including everything in its sub-collections. A smart
    /// collection answers from its rule instead of its members.
    func papers(inFolder id: Int?, recursive: Bool = true) -> [Paper] {
        guard let id else { return unfiled }
        if let f = folder(id), let rule = f.smartRule {
            return papers.filter { paper in
                rule.matches(paper, evidenceCount: evidence.filter { $0.paperId == paper.id }.count)
            }
        }
        var ids: Set<Int> = [id]
        if recursive {
            var frontier = [id]
            while let f = frontier.popLast() {
                for c in children(of: f) where !ids.contains(c.id) { ids.insert(c.id); frontier.append(c.id) }
            }
        }
        return papers.filter { p in !(membership[p.id]?.isDisjoint(with: ids) ?? true) }
    }

    /// Papers that are in no hand-made collection. Smart collections do not count, or
    /// nothing would ever look unfiled.
    var unfiled: [Paper] {
        let manual = Set(folders.filter { !$0.isSmart }.map(\.id))
        return papers.filter { (membership[$0.id] ?? []).isDisjoint(with: manual) }
    }

    @discardableResult
    func addFolder(name: String, parent: Int?, color: String = "#8A93A3",
                   rule: SmartRule? = nil) -> Int {
        do {
            let order = (folders.map(\.sortOrder).max() ?? -1) + 1
            let id = try db.run("""
                INSERT INTO folders (project_id,parent_id,name,color,sort_order,rule,icon)
                VALUES (?,?,?,?,?,?,?)
                """, [currentProjectId, parent, name, color, order, rule?.rawValue ?? "", rule?.icon ?? ""])
            reloadFolders()
            return Int(id)
        } catch { fail(error, "Creating collection"); return 0 }
    }

    func updateFolder(_ f: Folder) {
        do {
            try db.run("UPDATE folders SET name=?, color=?, parent_id=?, sort_order=?, rule=?, icon=? WHERE id=?",
                       [f.name, f.colorHex, f.parentId, f.sortOrder, f.rule, f.icon, f.id])
            reloadFolders()
        } catch { fail(error, "Saving collection") }
    }

    /// Deleting a collection deletes the label, never the papers or the files.
    func deleteFolder(_ id: Int) {
        do {
            try db.run("DELETE FROM folders WHERE id=?", [id])
            reloadFolders(); reloadMembership()
        } catch { fail(error, "Deleting collection") }
    }

    /// Kept for the places that still think in terms of moving. Filing a paper somewhere new
    /// no longer removes it from where it already was — that is the point of collections.
    func move(_ paperIds: [Int], toFolder id: Int?) {
        guard let id else {
            do {
                for pid in paperIds { try db.run("DELETE FROM paper_folders WHERE paper_id=?", [pid]) }
                reloadMembership()
            } catch { fail(error, "Unfiling papers") }
            return
        }
        addToCollection(paperIds, id)
    }

    // MARK: - Tags

    func reloadTags() {
        do {
            tags = try db.query("SELECT * FROM tags WHERE project_id=? ORDER BY kind, sort_order",
                                [currentProjectId]).map {
                Tag(id: $0.int("id") ?? 0, projectId: $0.int("project_id") ?? 0,
                    name: $0.string("name") ?? "", colorHex: $0.string("color") ?? Palette.yellowHex,
                    kind: $0.string("kind") ?? "category", detail: $0.string("detail") ?? "",
                    sortOrder: $0.int("sort_order") ?? 0, shortcut: $0.string("shortcut") ?? "")
            }
        } catch { fail(error, "Loading tags") }
    }

    func tag(_ id: Int) -> Tag? { tags.first { $0.id == id } }

    @discardableResult
    func addTag(name: String, color: String, kind: String, detail: String = "") -> Int {
        do {
            let order = (tags.filter { $0.kind == kind }.map(\.sortOrder).max() ?? -1) + 1
            let used = Set(tags.compactMap { $0.shortcut.isEmpty ? nil : $0.shortcut })
            let shortcut = kind == TagKind.type.rawValue
                ? ((1...9).map(String.init).first { !used.contains($0) } ?? "") : ""
            let id = try db.run("INSERT INTO tags (project_id,name,color,kind,detail,sort_order,shortcut) VALUES (?,?,?,?,?,?,?)",
                                [currentProjectId, name, color, kind, detail, order, shortcut])
            reloadTags()
            return Int(id)
        } catch { fail(error, "Adding tag"); return 0 }
    }

    func updateTag(_ t: Tag) {
        do {
            try db.run("UPDATE tags SET name=?, color=?, kind=?, detail=?, shortcut=?, sort_order=? WHERE id=?",
                       [t.name, t.colorHex, t.kind, t.detail, t.shortcut, t.sortOrder, t.id])
            reloadTags(); reloadEvidence()
        } catch { fail(error, "Saving tag") }
    }

    func deleteTag(_ id: Int) {
        do { try db.run("DELETE FROM tags WHERE id=?", [id]); reloadTags(); reloadEvidence() }
        catch { fail(error, "Deleting tag") }
    }

    func moveTag(_ id: Int, up: Bool) {
        guard let t = tag(id) else { return }
        let peers = tags.filter { $0.kind == t.kind }.sorted { $0.sortOrder < $1.sortOrder }
        guard let i = peers.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i - 1 : i + 1
        guard peers.indices.contains(j) else { return }
        var a = peers[i], b = peers[j]
        swap(&a.sortOrder, &b.sortOrder)
        updateTag(a); updateTag(b)
    }

    // MARK: - Evidence

    func reloadEvidence() {
        do {
            let rows = try db.query("SELECT * FROM evidence WHERE project_id=? ORDER BY paper_id, page, created_at",
                                    [currentProjectId])
            let links = try db.query("""
                SELECT et.evidence_id AS eid, et.tag_id AS tid FROM evidence_tags et
                JOIN evidence e ON e.id = et.evidence_id WHERE e.project_id=?
                """, [currentProjectId])
            var byEvidence: [Int: [Int]] = [:]
            for l in links { byEvidence[l.int("eid") ?? 0, default: []].append(l.int("tid") ?? 0) }
            evidence = rows.map { r in
                let eid = r.int("id") ?? 0
                return Evidence(id: eid,
                                projectId: r.int("project_id") ?? 0,
                                paperId: r.int("paper_id") ?? 0,
                                page: r.int("page") ?? -1,
                                quote: r.string("quote") ?? "",
                                note: r.string("note") ?? "",
                                colorHex: r.string("color") ?? Palette.yellowHex,
                                tagIds: byEvidence[eid] ?? [],
                                rects: Store.decodeRects(r.string("rects") ?? ""),
                                createdAt: r.date("created_at") ?? Date(),
                                aiGenerated: r.bool("ai_generated"),
                                kind: EvidenceKind(rawValue: r.string("kind") ?? "") ?? .quote,
                                stance: Stance(rawValue: r.string("stance") ?? "") ?? .evidence,
                                confidence: Confidence(rawValue: r.string("confidence") ?? "") ?? .medium,
                                verification: Verification(rawValue: r.string("verification") ?? "") ?? .unchecked)
            }
        } catch { fail(error, "Loading highlights") }
    }

    func evidence(forPaper id: Int) -> [Evidence] {
        evidence.filter { $0.paperId == id }.sorted { ($0.page, $0.createdAt) < ($1.page, $1.createdAt) }
    }

    @discardableResult
    func addEvidence(paperId: Int, page: Int, quote: String, note: String = "", color: String,
                     tagIds: [Int], rects: [CGRect], ai: Bool = false,
                     kind: EvidenceKind = .quote, stance: Stance = .evidence) -> Int {
        do {
            let id = try db.run("""
                INSERT INTO evidence (project_id, paper_id, page, quote, note, color, rects, created_at,
                                      ai_generated, kind, stance)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """, [currentProjectId, paperId, page, quote, note, color, Store.encodeRects(rects), Date(),
                      ai, kind.rawValue, stance.rawValue])
            for t in tagIds { try db.run("INSERT OR IGNORE INTO evidence_tags VALUES (?,?)", [Int(id), t]) }
            reloadEvidence()
            return Int(id)
        } catch { fail(error, "Saving highlight"); return 0 }
    }

    func updateEvidence(_ e: Evidence) {
        do {
            try db.run("""
                UPDATE evidence SET quote=?, note=?, color=?, page=?, rects=?, ai_generated=?,
                                    kind=?, stance=?, confidence=?, verification=? WHERE id=?
                """, [e.quote, e.note, e.colorHex, e.page, Store.encodeRects(e.rects), e.aiGenerated,
                      e.kind.rawValue, e.stance.rawValue, e.confidence.rawValue,
                      e.verification.rawValue, e.id])
            try db.run("DELETE FROM evidence_tags WHERE evidence_id=?", [e.id])
            for t in e.tagIds { try db.run("INSERT OR IGNORE INTO evidence_tags VALUES (?,?)", [e.id, t]) }
            reloadEvidence()
        } catch { fail(error, "Saving highlight") }
    }

    func deleteEvidence(_ id: Int) {
        do { try db.run("DELETE FROM evidence WHERE id=?", [id]); reloadEvidence() }
        catch { fail(error, "Deleting highlight") }
    }

    static func encodeRects(_ rects: [CGRect]) -> String {
        rects.map { "\($0.origin.x),\($0.origin.y),\($0.width),\($0.height)" }.joined(separator: ";")
    }

    static func decodeRects(_ s: String) -> [CGRect] {
        s.split(separator: ";").compactMap { part in
            let n = part.split(separator: ",").compactMap { Double($0) }
            guard n.count == 4 else { return nil }
            return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
        }
    }

    // MARK: - Frames

    func reloadFrames() {
        do {
            frames = try db.query("SELECT * FROM frames WHERE project_id=? ORDER BY sort_order, created_at",
                                  [currentProjectId]).map {
                Frame(id: $0.int("id") ?? 0, projectId: $0.int("project_id") ?? 0,
                      name: $0.string("name") ?? "", kind: $0.string("kind") ?? "custom",
                      detail: $0.string("detail") ?? "", sortOrder: $0.int("sort_order") ?? 0,
                      createdAt: $0.date("created_at") ?? Date())
            }
            var axes: [Int: [FrameAxis]] = [:]
            for r in try db.query("""
                SELECT a.* FROM frame_axes a JOIN frames f ON f.id = a.frame_id
                WHERE f.project_id=? ORDER BY a.sort_order
                """, [currentProjectId]) {
                let fid = r.int("frame_id") ?? 0
                axes[fid, default: []].append(FrameAxis(
                    id: r.int("id") ?? 0, frameId: fid,
                    isRow: (r.string("axis") ?? "row") == "row",
                    name: r.string("name") ?? "", detail: r.string("detail") ?? "",
                    sortOrder: r.int("sort_order") ?? 0, colorHex: r.string("color") ?? "",
                    sourceId: r.int("source_id")))
            }
            frameAxes = axes
            var cells: [String: FrameCell] = [:]
            for r in try db.query("""
                SELECT c.* FROM frame_cells c JOIN frames f ON f.id = c.frame_id WHERE f.project_id=?
                """, [currentProjectId]) {
                let fid = r.int("frame_id") ?? 0, row = r.int("row_id") ?? 0, col = r.int("col_id") ?? 0
                cells["\(fid)-\(row)-\(col)"] = FrameCell(
                    rowId: row, colId: col, value: r.string("value") ?? "",
                    evidenceIds: (r.string("evidence_ids") ?? "").split(separator: ",").compactMap { Int($0) },
                    aiGenerated: r.bool("ai_generated"))
            }
            frameCells = cells
        } catch { fail(error, "Loading frameworks") }
    }

    func rows(of frameId: Int) -> [FrameAxis] {
        (frameAxes[frameId] ?? []).filter(\.isRow).sorted { $0.sortOrder < $1.sortOrder }
    }
    func cols(of frameId: Int) -> [FrameAxis] {
        (frameAxes[frameId] ?? []).filter { !$0.isRow }.sorted { $0.sortOrder < $1.sortOrder }
    }
    func frameCell(_ frameId: Int, _ row: Int, _ col: Int) -> FrameCell {
        frameCells["\(frameId)-\(row)-\(col)"] ?? FrameCell(rowId: row, colId: col)
    }

    /// Creates a framework from a template, or empty when the method has open rows.
    @discardableResult
    func addFrame(_ template: FrameTemplate, name: String? = nil) -> Int {
        do {
            let order = (frames.map(\.sortOrder).max() ?? -1) + 1
            let id = Int(try db.run("""
                INSERT INTO frames (project_id, name, kind, detail, sort_order, created_at)
                VALUES (?,?,?,?,?,?)
                """, [currentProjectId, name ?? template.label, template.rawValue,
                      template.blurb, order, Date()]))
            let start = template.starting
            for (i, r) in start.rows.enumerated() { addAxis(id, isRow: true, name: r.0, detail: r.1, order: i) }
            for (i, c) in start.cols.enumerated() { addAxis(id, isRow: false, name: c.0, detail: c.1, order: i) }
            reloadFrames()
            return id
        } catch { fail(error, "Creating the framework"); return 0 }
    }

    @discardableResult
    func addAxis(_ frameId: Int, isRow: Bool, name: String, detail: String = "",
                 order: Int? = nil, sourceId: Int? = nil, color: String = "") -> Int {
        do {
            let existing = isRow ? rows(of: frameId) : cols(of: frameId)
            let sort = order ?? ((existing.map(\.sortOrder).max() ?? -1) + 1)
            let id = try db.run("""
                INSERT INTO frame_axes (frame_id, axis, name, detail, sort_order, color, source_id)
                VALUES (?,?,?,?,?,?,?)
                """, [frameId, isRow ? "row" : "col", name, detail, sort, color, sourceId])
            if order == nil { reloadFrames() }
            return Int(id)
        } catch { fail(error, "Adding to the framework"); return 0 }
    }

    func updateAxis(_ a: FrameAxis) {
        do {
            try db.run("UPDATE frame_axes SET name=?, detail=?, sort_order=?, color=?, source_id=? WHERE id=?",
                       [a.name, a.detail, a.sortOrder, a.colorHex, a.sourceId, a.id])
            reloadFrames()
        } catch { fail(error, "Saving") }
    }

    func deleteAxis(_ id: Int) {
        do { try db.run("DELETE FROM frame_axes WHERE id=?", [id]); reloadFrames() }
        catch { fail(error, "Removing") }
    }

    func moveAxis(_ id: Int, _ frameId: Int, isRow: Bool, up: Bool) {
        let list = isRow ? rows(of: frameId) : cols(of: frameId)
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i - 1 : i + 1
        guard list.indices.contains(j) else { return }
        var a = list[i], b = list[j]
        swap(&a.sortOrder, &b.sortOrder)
        updateAxis(a); updateAxis(b)
    }

    func setFrameCell(_ frameId: Int, _ row: Int, _ col: Int, value: String,
                      evidenceIds: [Int]? = nil, ai: Bool = false) {
        let existing = frameCell(frameId, row, col)
        let eids = evidenceIds ?? existing.evidenceIds
        do {
            try db.run("""
                INSERT INTO frame_cells (frame_id, row_id, col_id, value, evidence_ids, ai_generated)
                VALUES (?,?,?,?,?,?)
                ON CONFLICT(frame_id, row_id, col_id) DO UPDATE SET value=excluded.value,
                    evidence_ids=excluded.evidence_ids, ai_generated=excluded.ai_generated
                """, [frameId, row, col, value, eids.map(String.init).joined(separator: ","), ai])
            frameCells["\(frameId)-\(row)-\(col)"] = FrameCell(rowId: row, colId: col, value: value,
                                                                evidenceIds: eids, aiGenerated: ai)
        } catch { fail(error, "Saving the cell") }
    }

    func updateFrame(_ f: Frame) {
        do {
            try db.run("UPDATE frames SET name=?, detail=?, sort_order=? WHERE id=?",
                       [f.name, f.detail, f.sortOrder, f.id])
            reloadFrames()
        } catch { fail(error, "Saving the framework") }
    }

    func deleteFrame(_ id: Int) {
        do { try db.run("DELETE FROM frames WHERE id=?", [id]); reloadFrames() }
        catch { fail(error, "Deleting the framework") }
    }

    /// How much of a framework rests on cited evidence rather than assertion. The number a
    /// SWOT usually cannot answer.
    func frameGrounding(_ frameId: Int) -> (filled: Int, cited: Int, total: Int) {
        let r = rows(of: frameId), c = cols(of: frameId)
        var filled = 0, cited = 0
        for row in r {
            for col in c {
                let cell = frameCell(frameId, row.id, col.id)
                if !cell.value.isEmpty { filled += 1 }
                if !cell.evidenceIds.isEmpty { cited += 1 }
            }
        }
        return (filled, cited, r.count * c.count)
    }

    // MARK: - AI audit trail

    func reloadAIEvents() {
        do {
            aiEvents = try db.query("SELECT * FROM ai_events WHERE project_id=? ORDER BY at DESC",
                                    [currentProjectId]).map {
                AIEvent(id: $0.int("id") ?? 0,
                        projectId: $0.int("project_id") ?? 0,
                        at: $0.date("at") ?? Date(),
                        kind: AIEvent.Kind(rawValue: $0.string("kind") ?? "") ?? .screen,
                        model: $0.string("model") ?? "",
                        subjectKind: $0.string("subject_kind") ?? "",
                        subjectId: $0.int("subject_id") ?? 0,
                        columnId: $0.int("column_id") ?? 0,
                        asked: $0.string("asked") ?? "",
                        said: $0.string("said") ?? "",
                        confidence: $0.string("confidence") ?? "",
                        outcome: AIEvent.Outcome(rawValue: $0.string("outcome") ?? "") ?? .pending,
                        outcomeAt: $0.date("outcome_at"),
                        humanNote: $0.string("human_note") ?? "")
            }
        } catch { fail(error, "Loading the AI trail") }
    }

    /// Records what was asked and what came back, before anyone decides anything about it.
    @discardableResult
    func logAI(kind: AIEvent.Kind, model: String, subjectKind: String, subjectId: Int,
               columnId: Int = 0, asked: String, said: String, confidence: String = "") -> Int {
        do {
            let id = try db.run("""
                INSERT INTO ai_events (project_id, at, kind, model, subject_kind, subject_id,
                                       column_id, asked, said, confidence, outcome)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """, [currentProjectId, Date(), kind.rawValue, model, subjectKind, subjectId,
                      columnId, String(asked.prefix(4000)), String(said.prefix(8000)), confidence,
                      kind.needsAdjudication ? AIEvent.Outcome.pending.rawValue
                                             : AIEvent.Outcome.unused.rawValue])
            reloadAIEvents()
            return Int(id)
        } catch { fail(error, "Recording the AI trail"); return 0 }
    }

    /// The only field on an event that may change: what the human decided.
    func resolveAI(_ id: Int, _ outcome: AIEvent.Outcome, note: String = "") {
        guard id > 0 else { return }
        do {
            try db.run("UPDATE ai_events SET outcome=?, outcome_at=?, human_note=? WHERE id=?",
                       [outcome.rawValue, Date(), note, id])
            reloadAIEvents()
        } catch { fail(error, "Recording your verdict") }
    }

    /// Marks the most recent unresolved suggestion about a subject. Used from the decision
    /// points, where the event id is not to hand but the subject always is.
    func resolveLatestAI(subjectKind: String, subjectId: Int, columnId: Int = 0,
                         _ outcome: AIEvent.Outcome, note: String = "") {
        guard let event = aiEvents.first(where: {
            $0.subjectKind == subjectKind && $0.subjectId == subjectId
            && (columnId == 0 || $0.columnId == columnId) && $0.outcome == .pending
        }) else { return }
        resolveAI(event.id, outcome, note: note)
    }

    /// Everything the assistant produced that no one has adjudicated.
    var unresolvedAI: [AIEvent] {
        aiEvents.filter { $0.outcome == .pending && $0.kind.needsAdjudication }
    }

    struct AISummary {
        var total = 0
        var byKind: [(AIEvent.Kind, Int)] = []
        var byOutcome: [(AIEvent.Outcome, Int)] = []
        var pending = 0
        var models: [String] = []
        var firstUse: Date?
        var lastUse: Date?
        var everUsed: Bool { total > 0 }
        /// Included studies whose matrix cells were drafted by the model and never checked.
        var unverifiedInIncluded = 0
    }

    var aiSummary: AISummary {
        var s = AISummary()
        s.total = aiEvents.count
        guard !aiEvents.isEmpty else { return s }
        var kinds: [AIEvent.Kind: Int] = [:], outcomes: [AIEvent.Outcome: Int] = [:]
        for e in aiEvents { kinds[e.kind, default: 0] += 1; outcomes[e.outcome, default: 0] += 1 }
        s.byKind = kinds.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        s.byOutcome = outcomes.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        s.pending = unresolvedAI.count
        s.models = Array(Set(aiEvents.map(\.model).filter { !$0.isEmpty })).sorted()
        s.firstUse = aiEvents.map(\.at).min()
        s.lastUse = aiEvents.map(\.at).max()
        let includedIds = Set(included.map(\.id))
        s.unverifiedInIncluded = aiEvents.filter {
            $0.outcome == .pending && $0.kind.needsAdjudication
            && (($0.subjectKind == "paper" || $0.subjectKind == "cell") && includedIds.contains($0.subjectId))
        }.count
        return s
    }

    // MARK: - Relations

    func reloadRelations() {
        do {
            relations = try db.query("SELECT * FROM relations WHERE project_id=? ORDER BY created_at",
                                     [currentProjectId]).map {
                Relation(id: $0.int("id") ?? 0, projectId: $0.int("project_id") ?? 0,
                         fromKind: $0.string("from_kind") ?? "evidence", fromId: $0.int("from_id") ?? 0,
                         type: $0.string("type") ?? "supports",
                         toKind: $0.string("to_kind") ?? "evidence", toId: $0.int("to_id") ?? 0,
                         note: $0.string("note") ?? "", createdAt: $0.date("created_at") ?? Date())
            }
        } catch { fail(error, "Loading relations") }
    }

    @discardableResult
    func relate(_ from: (NodeKind, Int), _ type: RelationType, _ to: (NodeKind, Int),
                note: String = "") -> Int {
        // A link in either direction between the same two nodes is the same link.
        if relations.contains(where: {
            $0.type == type.rawValue &&
            (($0.fromId == from.1 && $0.fromKind == from.0.rawValue &&
              $0.toId == to.1 && $0.toKind == to.0.rawValue) ||
             ($0.fromId == to.1 && $0.fromKind == to.0.rawValue &&
              $0.toId == from.1 && $0.toKind == from.0.rawValue))
        }) { return 0 }
        do {
            let id = try db.run("""
                INSERT INTO relations (project_id, from_kind, from_id, type, to_kind, to_id, note, created_at)
                VALUES (?,?,?,?,?,?,?,?)
                """, [currentProjectId, from.0.rawValue, from.1, type.rawValue,
                      to.0.rawValue, to.1, note, Date()])
            reloadRelations()
            return Int(id)
        } catch { fail(error, "Linking"); return 0 }
    }

    func deleteRelation(_ id: Int) {
        do { try db.run("DELETE FROM relations WHERE id=?", [id]); reloadRelations() }
        catch { fail(error, "Removing link") }
    }

    /// Every link touching a node, in either direction.
    func relations(for kind: NodeKind, _ id: Int) -> [Relation] {
        relations.filter {
            ($0.fromKind == kind.rawValue && $0.fromId == id) ||
            ($0.toKind == kind.rawValue && $0.toId == id)
        }
    }

    func evidence(_ id: Int) -> Evidence? { evidence.first { $0.id == id } }

    // MARK: - Methods

    func reloadMethods() {
        do {
            methods = try db.query("""
                SELECT * FROM methods WHERE project_id=? OR project_id IS NULL ORDER BY is_template, name
                """, [currentProjectId]).map {
                Method(id: $0.int("id") ?? 0,
                       projectId: $0.int("project_id"),
                       name: $0.string("name") ?? "",
                       detail: $0.string("detail") ?? "",
                       blocks: ($0.string("blocks") ?? "").split(separator: ",")
                           .compactMap { MethodBlock(rawValue: String($0)) },
                       isTemplate: $0.bool("is_template"),
                       currentStep: $0.int("current_step") ?? 0)
            }
        } catch { fail(error, "Loading methods") }
    }

    var activeMethod: Method? { methods.first { $0.projectId == currentProjectId } }

    @discardableResult
    func saveMethod(_ m: Method) -> Int {
        do {
            let blocks = m.blocks.map(\.rawValue).joined(separator: ",")
            if m.id > 0 {
                try db.run("UPDATE methods SET name=?, detail=?, blocks=?, is_template=?, current_step=? WHERE id=?",
                           [m.name, m.detail, blocks, m.isTemplate, m.currentStep, m.id])
                reloadMethods()
                return m.id
            }
            let id = try db.run("INSERT INTO methods (project_id,name,detail,blocks,is_template,current_step) VALUES (?,?,?,?,?,?)",
                                [m.projectId, m.name, m.detail, blocks, m.isTemplate, m.currentStep])
            reloadMethods()
            return Int(id)
        } catch { fail(error, "Saving method"); return 0 }
    }

    func deleteMethod(_ id: Int) {
        do { try db.run("DELETE FROM methods WHERE id=?", [id]); reloadMethods() }
        catch { fail(error, "Deleting method") }
    }

    /// Applies a saved recipe to this review, replacing whatever method it had.
    func adopt(_ template: Method) {
        if let existing = activeMethod { deleteMethod(existing.id) }
        var m = template
        m.id = 0
        m.projectId = currentProjectId
        m.isTemplate = false
        m.currentStep = 0
        saveMethod(m)
    }

    // MARK: - PRISMA counts entered by hand

    func reloadPrismaCounts() {
        do {
            var out: [String: Int] = [:]
            for r in try db.query("SELECT key, value FROM prisma_counts WHERE project_id=?", [currentProjectId]) {
                out[r.string("key") ?? ""] = r.int("value") ?? 0
            }
            prismaCounts = out
        } catch { fail(error, "Loading PRISMA counts") }
    }

    func prismaCount(_ key: String) -> Int { prismaCounts[key] ?? 0 }

    func setPrismaCount(_ key: String, _ value: Int) {
        do {
            try db.run("""
                INSERT INTO prisma_counts (project_id, key, value) VALUES (?,?,?)
                ON CONFLICT(project_id, key) DO UPDATE SET value=excluded.value
                """, [currentProjectId, key, max(0, value)])
            prismaCounts[key] = max(0, value)
        } catch { fail(error, "Saving count") }
    }

    var prismaVariant: PrismaVariant {
        get { PrismaVariant(rawValue: UserDefaults.standard.string(forKey: "sieve.prismaVariant.\(currentProjectId)") ?? "") ?? .newV1 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sieve.prismaVariant.\(currentProjectId)"); objectWillChange.send() }
    }

    // MARK: - Reporting checklist

    func reloadChecklist() {
        do {
            var out: [String: (String, String)] = [:]
            for r in try db.query("SELECT item, state, location FROM checklist WHERE project_id=?",
                                  [currentProjectId]) {
                out[r.string("item") ?? ""] = (r.string("state") ?? "todo", r.string("location") ?? "")
            }
            checklist = out
        } catch { fail(error, "Loading checklist") }
    }

    func setChecklist(_ item: String, state: String, location: String) {
        do {
            try db.run("""
                INSERT INTO checklist (project_id, item, state, location) VALUES (?,?,?,?)
                ON CONFLICT(project_id, item) DO UPDATE SET state=excluded.state, location=excluded.location
                """, [currentProjectId, item, state, location])
            checklist[item] = (state, location)
        } catch { fail(error, "Saving checklist") }
    }

    // MARK: - Matrix

    func reloadColumns() {
        do {
            columns = try db.query("SELECT * FROM matrix_columns WHERE project_id=? ORDER BY sort_order",
                                   [currentProjectId]).map {
                MatrixColumn(id: $0.int("id") ?? 0, projectId: $0.int("project_id") ?? 0,
                             name: $0.string("name") ?? "", prompt: $0.string("prompt") ?? "",
                             sortOrder: $0.int("sort_order") ?? 0, width: $0.double("width") ?? 220)
            }
        } catch { fail(error, "Loading matrix columns") }
    }

    func reloadCells() {
        do {
            let rows = try db.query("""
                SELECT c.* FROM matrix_cells c JOIN papers p ON p.id = c.paper_id WHERE p.project_id=?
                """, [currentProjectId])
            var map: [String: MatrixCell] = [:]
            for r in rows {
                let pid = r.int("paper_id") ?? 0, cid = r.int("column_id") ?? 0
                map["\(pid)-\(cid)"] = MatrixCell(
                    paperId: pid, columnId: cid,
                    value: r.string("value") ?? "",
                    evidenceIds: (r.string("evidence_ids") ?? "").split(separator: ",").compactMap { Int($0) },
                    aiGenerated: r.bool("ai_generated"))
            }
            cells = map
        } catch { fail(error, "Loading matrix") }
    }

    func cell(_ paperId: Int, _ columnId: Int) -> MatrixCell {
        cells["\(paperId)-\(columnId)"] ?? MatrixCell(paperId: paperId, columnId: columnId)
    }

    func setCell(_ paperId: Int, _ columnId: Int, value: String, evidenceIds: [Int]? = nil, ai: Bool = false) {
        let existing = cell(paperId, columnId)
        let eids = evidenceIds ?? existing.evidenceIds
        do {
            try db.run("""
                INSERT INTO matrix_cells (paper_id, column_id, value, evidence_ids, ai_generated) VALUES (?,?,?,?,?)
                ON CONFLICT(paper_id, column_id) DO UPDATE SET value=excluded.value,
                    evidence_ids=excluded.evidence_ids, ai_generated=excluded.ai_generated
                """, [paperId, columnId, value, eids.map(String.init).joined(separator: ","), ai])
            cells["\(paperId)-\(columnId)"] = MatrixCell(paperId: paperId, columnId: columnId,
                                                         value: value, evidenceIds: eids, aiGenerated: ai)
        } catch { fail(error, "Saving cell") }
    }

    @discardableResult
    func addColumn(name: String, prompt: String = "") -> Int {
        do {
            let order = (columns.map(\.sortOrder).max() ?? -1) + 1
            let id = try db.run("INSERT INTO matrix_columns (project_id,name,prompt,sort_order) VALUES (?,?,?,?)",
                                [currentProjectId, name, prompt, order])
            reloadColumns()
            return Int(id)
        } catch { fail(error, "Adding column"); return 0 }
    }

    func updateColumn(_ c: MatrixColumn) {
        do {
            try db.run("UPDATE matrix_columns SET name=?, prompt=?, width=?, sort_order=? WHERE id=?",
                       [c.name, c.prompt, c.width, c.sortOrder, c.id])
            reloadColumns()
        } catch { fail(error, "Saving column") }
    }

    func deleteColumn(_ id: Int) {
        do { try db.run("DELETE FROM matrix_columns WHERE id=?", [id]); reloadColumns(); reloadCells() }
        catch { fail(error, "Deleting column") }
    }

    func moveColumn(_ id: Int, left: Bool) {
        let sorted = columns.sorted { $0.sortOrder < $1.sortOrder }
        guard let i = sorted.firstIndex(where: { $0.id == id }) else { return }
        let j = left ? i - 1 : i + 1
        guard sorted.indices.contains(j) else { return }
        var a = sorted[i], b = sorted[j]
        swap(&a.sortOrder, &b.sortOrder)
        updateColumn(a); updateColumn(b)
    }

    // MARK: - Search run log (feeds PRISMA "records identified from…")

    func logSearchRun(query: String, providers: [String], results: Int, imported: Int) {
        do {
            try db.run("INSERT INTO search_runs (project_id,query,providers,n_results,n_imported,run_at) VALUES (?,?,?,?,?,?)",
                       [currentProjectId, query, providers.joined(separator: ", "), results, imported, Date()])
        } catch { fail(error, "Logging search") }
    }

    func searchRuns() -> [(query: String, providers: String, results: Int, imported: Int, at: Date)] {
        (try? db.query("SELECT * FROM search_runs WHERE project_id=? ORDER BY run_at DESC", [currentProjectId]))?
            .map { ($0.string("query") ?? "", $0.string("providers") ?? "",
                    $0.int("n_results") ?? 0, $0.int("n_imported") ?? 0, $0.date("run_at") ?? Date()) } ?? []
    }

    // MARK: - PRISMA counts, derived from stages

    /// The PRISMA 2020 flow, as the official templates define it. Screening decisions supply
    /// what they can; the counts PRISMA asks for that no decision implies — registers,
    /// automation-tool removals, records found through websites or citation searching, and an
    /// updated review's previous version — come from the numbers you enter on the diagram.
    struct Prisma {
        // Identification
        var fromDatabases = 0
        var fromRegisters = 0
        var perSource: [(String, Int)] = []
        var duplicates = 0
        var automationRemoved = 0
        var otherRemoved = 0
        var removedBeforeScreening = 0

        // Screening
        var screened = 0
        var excludedScreening = 0
        var sought = 0
        var notRetrieved = 0
        var assessed = 0
        var excludedEligibility = 0
        var exclusionReasons: [(String, Int)] = []
        /// Records past screening with no readable full text on disk.
        var unevidencedFullTexts = 0
        var includedWithoutFullText = 0

        // Other methods (v2 diagrams)
        var otherWebsites = 0
        var otherOrganisations = 0
        var otherCitation = 0
        var otherIdentified = 0
        var otherSought = 0
        var otherNotRetrieved = 0
        var otherAssessed = 0
        var otherExcluded = 0
        var otherIncluded = 0

        // Previous version (updated-review diagrams)
        var previousStudies = 0
        var previousReports = 0

        // Included
        var includedStudies = 0
        var includedReports = 0
        var totalStudies = 0
        var totalReports = 0

        /// Kept for the parts of the app that just want "how many records in total".
        var identified: Int { fromDatabases + fromRegisters }
        var included: Int { includedStudies }
    }

    var prisma: Prisma {
        var p = Prisma()
        let registers = prismaCount(PrismaKey.registers)

        p.fromRegisters = registers
        p.fromDatabases = max(papers.count - registers, 0)

        var bySource: [String: Int] = [:]
        for paper in papers {
            let key = paper.sourceDB.isEmpty ? "Manual / hand-added" : paper.sourceDB
            bySource[key, default: 0] += 1
        }
        p.perSource = bySource.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        p.duplicates = papers.filter { $0.stage == .duplicate }.count
        p.automationRemoved = prismaCount(PrismaKey.automationRemoved)
        p.otherRemoved = prismaCount(PrismaKey.otherRemoved)
        p.removedBeforeScreening = p.duplicates + p.automationRemoved + p.otherRemoved

        p.screened = max(p.identified - p.removedBeforeScreening, 0)
        p.excludedScreening = papers.filter { $0.stage == .excludedScreening }.count
            + prismaCount(PrismaKey.automationExcluded)
        // A report is retrieved only if the full text is genuinely on disk. Records that
        // passed screening but were never actually obtained belong in "not retrieved",
        // otherwise the diagram claims full texts that were never read.
        let markedNotRetrieved = papers.filter { $0.stage == .notRetrieved }
        let missingFullText = strictRetrieval
            ? papers.filter {
                [.sought, .eligibility, .excludedEligibility, .included].contains($0.stage) && !$0.hasPDF
              }
            : []
        p.unevidencedFullTexts = missingFullText.count
        p.notRetrieved = markedNotRetrieved.count + missingFullText.count
        p.excludedEligibility = papers.filter { $0.stage == .excludedEligibility }.count

        let untriaged = papers.filter { $0.stage == .identified || $0.stage == .screening }.count
        p.sought = max(p.screened - p.excludedScreening - untriaged, 0)
        p.assessed = max(p.sought - p.notRetrieved, 0)

        var reasons: [String: Int] = [:]
        for paper in papers where paper.stage == .excludedEligibility {
            reasons[paper.excludeReason.isEmpty ? "Reason not recorded" : paper.excludeReason, default: 0] += 1
        }
        p.exclusionReasons = reasons.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        p.otherWebsites = prismaCount(PrismaKey.websites)
        p.otherOrganisations = prismaCount(PrismaKey.organisations)
        p.otherCitation = prismaCount(PrismaKey.citationSearching)
        p.otherIdentified = p.otherWebsites + p.otherOrganisations + p.otherCitation
        p.otherSought = prismaCount(PrismaKey.otherSought)
        p.otherNotRetrieved = prismaCount(PrismaKey.otherNotRetrieved)
        p.otherAssessed = prismaCount(PrismaKey.otherAssessed)
        p.otherExcluded = prismaCount(PrismaKey.otherExcluded)
        p.otherIncluded = prismaCount(PrismaKey.otherIncluded)

        p.previousStudies = prismaCount(PrismaKey.previousStudies)
        p.previousReports = prismaCount(PrismaKey.previousReports)

        // Included studies must have a full text behind them for the same reason.
        let inc = strictRetrieval
            ? papers.filter { $0.stage == .included && $0.hasPDF }
            : papers.filter { $0.stage == .included }
        p.includedWithoutFullText = papers.filter { $0.stage == .included && !$0.hasPDF }.count
        p.includedStudies = inc.count + p.otherIncluded
        // PRISMA counts studies and the reports of them separately: one study can be
        // published across several papers.
        p.includedReports = inc.reduce(0) { $0 + max($1.reportCount, 1) } + p.otherIncluded
        p.totalStudies = p.includedStudies + p.previousStudies
        p.totalReports = p.includedReports + p.previousReports
        return p
    }

    /// When on, PRISMA treats a readable PDF on disk as the proof that a report was
    /// retrieved. Off, it trusts the screening decisions alone — useful only if you keep
    /// full texts outside Sieve.
    var strictRetrieval: Bool {
        get { UserDefaults.standard.object(forKey: "sieve.strictRetrieval") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sieve.strictRetrieval"); objectWillChange.send() }
    }

    /// Records that claim to be past retrieval but have no readable full text.
    var missingFullTexts: [Paper] {
        papers.filter {
            [.sought, .eligibility, .excludedEligibility, .included].contains($0.stage) && !$0.hasPDF
        }
    }

    /// Records whose stored file has gone missing or is not a readable PDF.
    var brokenPDFs: [Paper] { papers.filter(\.pdfBroken) }

    /// The papers behind any number on the flow diagram, so every count is clickable.
    func papers(forPrismaBox box: PrismaBox) -> [Paper] {
        switch box {
        case .identified:      return papers
        case .removedBefore:   return papers.filter { $0.stage == .duplicate }
        case .screened:        return papers.filter { $0.stage != .duplicate }
        case .excludedScreen:  return papers.filter { $0.stage == .excludedScreening }
        case .sought:          return papers.filter {
            [.sought, .notRetrieved, .eligibility, .excludedEligibility, .included].contains($0.stage) }
        case .notRetrieved:    return papers.filter { $0.stage == .notRetrieved }
            + (strictRetrieval ? missingFullTexts : [])
        case .assessed:        return papers.filter {
            [.eligibility, .excludedEligibility, .included].contains($0.stage)
            && (!strictRetrieval || $0.hasPDF) }
        case .excludedFull:    return papers.filter { $0.stage == .excludedEligibility }
        case .included:        return papers.filter {
            $0.stage == .included && (!strictRetrieval || $0.hasPDF) }
        }
    }

    // MARK: - What am I missing?

    /// Structural weaknesses in the review, computed rather than guessed. Each one names the
    /// records involved so it can be acted on rather than just worried about.
    struct Gap: Identifiable {
        var id: String
        var title: String
        var detail: String
        var count: Int
        var severity: Severity
        var section: String
        enum Severity { case info, warn, serious }
    }

    var gaps: [Gap] {
        var out: [Gap] = []
        let inc = included

        let untriaged = papers.filter { $0.stage == .identified || $0.stage == .screening }
        if !untriaged.isEmpty {
            out.append(.init(id: "untriaged", title: "Records not yet screened",
                             detail: "\(untriaged.count) record\(untriaged.count == 1 ? " has" : "s have") no decision, so the flow diagram doesn't add up yet.",
                             count: untriaged.count, severity: .serious, section: "screening"))
        }

        let noReason = papers.filter { $0.stage == .excludedEligibility && $0.excludeReason.isEmpty }
        if !noReason.isEmpty {
            out.append(.init(id: "noreason", title: "Full-text exclusions with no reason",
                             detail: "PRISMA item 16b requires a reason for every report excluded after reading it.",
                             count: noReason.count, severity: .serious, section: "screening"))
        }

        let unread = inc.filter { evidence(forPaper: $0.id).isEmpty }
        if !unread.isEmpty {
            out.append(.init(id: "unread", title: "Included papers with no highlights",
                             detail: "Nothing has been extracted from \(unread.count) of the \(inc.count) papers in the review.",
                             count: unread.count, severity: .warn, section: "reader"))
        }

        let noPDF = inc.filter { !$0.hasPDF }
        if !noPDF.isEmpty {
            out.append(.init(id: "nopdf", title: "Included papers with no full text",
                             detail: strictRetrieval
                                ? "PRISMA is not counting these as included, because there is no PDF on disk to prove the report was retrieved."
                                : "You can't assess what you can't read. Fetch or attach these PDFs.",
                             count: noPDF.count, severity: .serious, section: "library"))
        }

        let unevidenced = missingFullTexts.filter { $0.stage != .included }
        if !unevidenced.isEmpty {
            out.append(.init(id: "unevidenced", title: "Full texts sought but never obtained",
                             detail: "These passed title/abstract screening but no PDF was ever downloaded. PRISMA counts them as “not retrieved”.",
                             count: unevidenced.count, severity: .warn, section: "library"))
        }

        let broken = brokenPDFs
        if !broken.isEmpty {
            out.append(.init(id: "brokenpdf", title: "Attached files that can't be read",
                             detail: "The record points at a file that has been moved, deleted, or isn't a readable PDF.",
                             count: broken.count, severity: .serious, section: "library"))
        }

        let unverified = evidence.filter { $0.stance == .evidence && $0.verification == .unchecked }
        if unverified.count > 5 {
            out.append(.init(id: "unverified", title: "Evidence not checked against its source",
                             detail: "\(unverified.count) highlights are still marked as needing a check.",
                             count: unverified.count, severity: .info, section: "evidence"))
        }

        let conflicting = evidence.filter { $0.verification == .conflicting }
        if !conflicting.isEmpty {
            out.append(.init(id: "conflicting", title: "Conflicting evidence",
                             detail: "You have flagged \(conflicting.count) passages as in conflict with something else.",
                             count: conflicting.count, severity: .warn, section: "evidence"))
        }

        let contradictions = relations.filter { $0.type == RelationType.contradicts.rawValue }
        if !contradictions.isEmpty {
            out.append(.init(id: "contradicts", title: "Contradictions recorded",
                             detail: "\(contradictions.count) link\(contradictions.count == 1 ? "" : "s") in the evidence graph say two sources disagree.",
                             count: contradictions.count, severity: .info, section: "map"))
        }

        // A claim or interpretation with nothing supporting it is the classic weak point.
        // Questions are exempt: an open question is meant to be unanswered.
        let claims = evidence.filter {
            $0.stance != .question && ($0.stance == .interpretation || $0.kind == .claim)
        }
        let supported = Set(relations
            .filter { $0.type == RelationType.supports.rawValue && $0.toKind == NodeKind.evidence.rawValue }
            .map(\.toId))
        let unsupported = claims.filter { !supported.contains($0.id) }
        if !unsupported.isEmpty {
            out.append(.init(id: "unsupported", title: "Interpretations with no evidence linked",
                             detail: "\(unsupported.count) of your own interpretations aren't linked to anything a source actually says.",
                             count: unsupported.count, severity: .warn, section: "evidence"))
        }

        // A theme resting on a single paper is not yet a finding.
        let themeTags = tags.filter { $0.tagKind == .theme || $0.tagKind == .type }
        var thin: [String] = []
        for t in themeTags {
            let papersUsing = Set(evidence.filter { $0.tagIds.contains(t.id) }.map(\.paperId))
            if papersUsing.count == 1 { thin.append(t.name) }
        }
        if !thin.isEmpty {
            out.append(.init(id: "singlesource", title: "Categories resting on one source",
                             detail: thin.prefix(6).joined(separator: ", ")
                                 + (thin.count > 6 ? " and \(thin.count - 6) more" : "")
                                 + " appear in only one paper.",
                             count: thin.count, severity: .info, section: "evidence"))
        }

        let openQuestions = evidence.filter { $0.stance == .question }
        if !openQuestions.isEmpty {
            out.append(.init(id: "questions", title: "Open questions",
                             detail: "\(openQuestions.count) things you wrote down as not yet known.",
                             count: openQuestions.count, severity: .info, section: "evidence"))
        }

        let noConclusion = inc.filter { $0.conclusion.isEmpty && $0.extractedConclusion.isEmpty }
        if !noConclusion.isEmpty {
            out.append(.init(id: "noconclusion", title: "Included papers with no conclusion recorded",
                             detail: "Neither yours nor one Sieve could read out of the PDF.",
                             count: noConclusion.count, severity: .info, section: "screening"))
        }

        let doneItems = checklist.values.filter { $0.state == "done" }.count
        if doneItems < PrismaChecklist.items.count {
            out.append(.init(id: "checklist", title: "PRISMA checklist incomplete",
                             detail: "\(doneItems) of \(PrismaChecklist.items.count) reporting items marked done.",
                             count: PrismaChecklist.items.count - doneItems,
                             severity: .info, section: "prisma"))
        }
        return out
    }

    var pendingScreening: [Paper] {
        papers.filter { $0.stage == .identified || $0.stage == .screening }
    }
    var pendingFullText: [Paper] {
        papers.filter { $0.stage == .sought || $0.stage == .eligibility }
    }
    /// Records that already have a decision — the list you reopen to change your mind.
    var decided: [Paper] {
        papers.filter { $0.stage != .identified && $0.stage != .screening }
            .sorted { $0.addedAt > $1.addedAt }
    }

    var included: [Paper] {
        papers.filter { $0.stage == .included }.sorted {
            ($0.year ?? 0, $0.authorLine) < ($1.year ?? 0, $1.authorLine)
        }
    }
}

// Tuple comparison helper used above.
private func < <A: Comparable, B: Comparable>(l: (A, B), r: (A, B)) -> Bool {
    l.0 == r.0 ? l.1 < r.1 : l.0 < r.0
}
