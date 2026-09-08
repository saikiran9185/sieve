import Foundation

/// Names files so they identify themselves in Finder.
///
/// The old scheme stripped a title to ASCII letters, which turns a Cyrillic or Greek title
/// into a row of underscores. Titles are transliterated first, and every name is prefixed
/// with author and year so a folder of PDFs sorts into something a person can read.
enum PDFNaming {
    static func filename(for paper: Paper) -> String {
        let author = surname(paper.authors.first) ?? "anon"
        let year = paper.year.map(String.init) ?? "nd"
        let title = slug(paper.title)
        let stem = title.isEmpty ? "\(year)-\(author)" : "\(year)-\(author)-\(title)"
        return String(stem.prefix(90)) + ".pdf"
    }

    private static func surname(_ full: String?) -> String? {
        guard let full, !full.isEmpty else { return nil }
        // "Smith, Jane" and "Jane Smith" both yield "Smith".
        let name = full.contains(",")
            ? full.components(separatedBy: ",")[0]
            : (full.split(separator: " ").last.map(String.init) ?? full)
        let s = slug(name)
        return s.isEmpty ? nil : String(s.prefix(24))
    }

    /// Transliterates to Latin, drops diacritics, then keeps what a file system is happy with.
    static func slug(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        let cleaned = plain
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned
    }

    /// Safe for a folder name: no separators, no leading dot, never empty.
    static func folderName(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(cleaned.prefix(60))
        if trimmed.isEmpty || trimmed.hasPrefix(".") { return "Untitled" }
        return trimmed
    }
}

/// A browsable copy of the review's structure, made of symbolic links.
///
/// The papers themselves stay in one flat `PDFs` folder — one file per paper, ever. A
/// collection is a label and a paper can carry several, so it cannot physically live in
/// several directories. `Browse` gives the Finder view anyway: the same file appears under
/// every collection, stage and year it belongs to, at no cost in disk space, and deleting
/// the whole folder loses nothing.
@MainActor
enum FinderMirror {

    enum Grouping: String, CaseIterable, Identifiable {
        case collection, stage, year, author, source
        var id: String { rawValue }

        var label: String {
            switch self {
            case .collection: return "By collection"
            case .stage: return "By screening decision"
            case .year: return "By year"
            case .author: return "By first author"
            case .source: return "By database"
            }
        }

        var blurb: String {
            switch self {
            case .collection: return "One folder per collection, smart ones included. A paper appears under each collection it is in."
            case .stage: return "Included, excluded with the reason, still to screen."
            case .year: return "One folder per publication year."
            case .author: return "One folder per first author."
            case .source: return "Which database the record came from."
            }
        }
    }

    static var enabledGroupings: Set<Grouping> {
        get {
            let saved = UserDefaults.standard.stringArray(forKey: "sieve.mirrorGroupings")
                ?? [Grouping.stage.rawValue, Grouping.collection.rawValue]
            return Set(saved.compactMap(Grouping.init))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: "sieve.mirrorGroupings")
        }
    }

    static var autoRefresh: Bool {
        get { UserDefaults.standard.object(forKey: "sieve.mirrorAuto") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "sieve.mirrorAuto") }
    }

    struct Result {
        var folders = 0
        var links = 0
        var skipped = 0
    }

    static func browseDir(id: Int, name: String) -> URL {
        Library.reviewDir(id: id, name: name).appendingPathComponent("Browse", isDirectory: true)
    }

    /// Rebuilds the whole mirror from scratch. Cheap — it only ever writes symlinks.
    @discardableResult
    static func rebuild(_ store: Store) -> Result {
        guard let project = store.project else { return Result() }
        let fm = FileManager.default
        let browse = browseDir(id: project.id, name: project.name)
        try? fm.removeItem(at: browse)

        var result = Result()
        let groupings = enabledGroupings
        guard !groupings.isEmpty else { return result }
        try? fm.createDirectory(at: browse, withIntermediateDirectories: true)

        for grouping in Grouping.allCases where groupings.contains(grouping) {
            let root = browse.appendingPathComponent(grouping.label, isDirectory: true)
            for (folderPath, papers) in buckets(for: grouping, store: store) {
                guard !papers.isEmpty else { continue }
                var dir = root
                for component in folderPath { dir.appendPathComponent(PDFNaming.folderName(component)) }
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                result.folders += 1

                for paper in papers {
                    guard paper.hasPDF else { result.skipped += 1; continue }
                    let source = URL(fileURLWithPath: paper.pdfPath)
                    var link = dir.appendingPathComponent(source.lastPathComponent)
                    var n = 2
                    while fm.fileExists(atPath: link.path) {
                        let stem = source.deletingPathExtension().lastPathComponent
                        link = dir.appendingPathComponent("\(stem)~\(n).pdf"); n += 1
                    }
                    // Relative, so the whole review folder can be moved or zipped intact.
                    let relative = relativePath(from: link.deletingLastPathComponent(), to: source)
                    do {
                        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: relative)
                        result.links += 1
                    } catch { result.skipped += 1 }
                }
            }
        }

        writeReadme(project: project, store: store)
        return result
    }

    private static func buckets(for grouping: Grouping, store: Store) -> [([String], [Paper])] {
        let papers = store.papers.filter(\.hasPDF)
        switch grouping {
        case .collection:
            var out: [([String], [Paper])] = []
            for folder in store.folders {
                let members = store.papers(inFolder: folder.id).filter(\.hasPDF)
                var path = [folder.name]
                // Nest sub-collections the way they nest in the sidebar.
                var cursor = folder
                while let pid = cursor.parentId, let parent = store.folder(pid) {
                    path.insert(parent.name, at: 0); cursor = parent
                }
                if folder.isSmart { path[0] = path[0] + " (fills itself)" }
                out.append((path, members))
            }
            let unfiled = store.unfiled.filter(\.hasPDF)
            if !unfiled.isEmpty { out.append((["Not in any collection"], unfiled)) }
            return out

        case .stage:
            var out: [([String], [Paper])] = []
            for stage in Stage.allCases {
                let group = papers.filter { $0.stage == stage }
                guard !group.isEmpty else { continue }
                if stage == .excludedEligibility || stage == .excludedScreening {
                    // Excluded papers sort under the reason they were excluded for — the
                    // thing you go looking for when writing the review up.
                    let byReason = Dictionary(grouping: group) {
                        $0.excludeReason.isEmpty ? "Reason not recorded" : $0.excludeReason
                    }
                    for (reason, list) in byReason { out.append(([stage.label, reason], list)) }
                } else {
                    out.append(([stage.label], group))
                }
            }
            return out

        case .year:
            return Dictionary(grouping: papers) { $0.year.map(String.init) ?? "No year" }
                .map { ([$0.key], $0.value) }

        case .author:
            return Dictionary(grouping: papers) { paper -> String in
                guard let first = paper.authors.first, !first.isEmpty else { return "Unknown author" }
                return first.contains(",")
                    ? first.components(separatedBy: ",")[0].trimmingCharacters(in: .whitespaces)
                    : (first.split(separator: " ").last.map(String.init) ?? first)
            }.map { ([$0.key], $0.value) }

        case .source:
            return Dictionary(grouping: papers) {
                $0.sourceDB.isEmpty ? "Added by hand" : $0.sourceDB
            }.map { ([$0.key], $0.value) }
        }
    }

    /// A relative path from one directory to a file, so links survive the folder being moved.
    private static func relativePath(from dir: URL, to file: URL) -> String {
        let from = dir.standardizedFileURL.pathComponents
        let to = file.standardizedFileURL.pathComponents
        var i = 0
        while i < from.count, i < to.count, from[i] == to[i] { i += 1 }
        let up = Array(repeating: "..", count: from.count - i)
        return (up + to[i...]).joined(separator: "/")
    }

    private static func writeReadme(project: Project, store: Store) {
        let dir = Library.reviewDir(id: project.id, name: project.name)
        let text = """
        \(project.name)

        \(project.question.isEmpty ? "" : project.question + "\n")
        PDFs/
            Every paper in this review, one file each. This is the only copy — nothing here
            is duplicated, whatever else it appears under.

        Browse/
            A view of the same files, arranged into folders. Everything inside is a symbolic
            link, not a copy: a paper that belongs to three collections shows up in all three
            and still takes up space once. You can delete this whole folder at any time and
            lose nothing; Sieve will rebuild it on request.

        Collections in Sieve are labels rather than locations, which is why the papers
        themselves stay flat. Browse/ exists so Finder can show you the structure anyway.

        \(store.papers.count) records · \(store.papers.filter(\.hasPDF).count) with a full text
        Rebuilt \(Date().formatted(date: .long, time: .shortened)) by Sieve.
        """
        try? text.write(to: dir.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    /// Renames the stored files to the author-year-title scheme, fixing names an older build
    /// reduced to underscores when the title was not in the Latin alphabet.
    @discardableResult
    static func renameFiles(_ store: Store) -> Int {
        guard let project = store.project else { return 0 }
        let fm = FileManager.default
        let dir = Library.pdfDir(id: project.id, name: project.name)
        var renamed = 0
        for paper in store.papers where paper.hasPDF {
            let current = URL(fileURLWithPath: paper.pdfPath)
            let wanted = PDFNaming.filename(for: paper)
            guard current.lastPathComponent != wanted else { continue }
            var dest = dir.appendingPathComponent(wanted)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                dest = dir.appendingPathComponent(
                    String(wanted.dropLast(4)) + "-\(n).pdf"); n += 1
            }
            do {
                try fm.moveItem(at: current, to: dest)
                store.setPDFPath(paper.id, dest.path)
                renamed += 1
            } catch { continue }
        }
        if renamed > 0 { PDFVault.invalidateAll(); store.reloadPapers() }
        return renamed
    }
}
