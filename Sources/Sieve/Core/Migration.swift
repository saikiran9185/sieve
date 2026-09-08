import Foundation

/// One-time repairs to the library on disk.
///
/// Early versions kept every review's PDFs in a single shared folder and stored absolute
/// paths to them, and the importer copied a file before checking whether the record already
/// existed — so re-dropping the same paper wrote `foo-2.pdf`, `foo-3.pdf`, and orphaned
/// whatever came before. This puts that right: each review gets its own folder, paths become
/// relative to the library root so the library can be moved, and files nothing points at are
/// collected up for the user to delete.
@MainActor
enum LibraryMigration {

    struct Report {
        var moved = 0
        var alreadyPlaced = 0
        var missing = 0
        var orphans: [URL] = []
        var orphanBytes = 0
        var isEmpty: Bool { moved == 0 && orphans.isEmpty && missing == 0 }
    }

    /// Files that are still in the shared folder or outside the review that owns them.
    static func needsMigration(_ store: Store) -> Bool {
        for project in store.projects {
            let home = Library.pdfDir(id: project.id, name: project.name).path
            for p in store.papersRaw(projectId: project.id) where !p.pdfPath.isEmpty {
                if !p.pdfPath.hasPrefix(home) { return true }
            }
        }
        return false
    }

    @discardableResult
    static func run(_ store: Store, deleteOrphans: Bool = false) -> Report {
        var report = Report()
        let fm = FileManager.default
        var claimed = Set<String>()

        for project in store.projects {
            let home = Library.pdfDir(id: project.id, name: project.name)
            try? fm.createDirectory(at: home, withIntermediateDirectories: true)

            for paper in store.papersRaw(projectId: project.id) where !paper.pdfPath.isEmpty {
                let current = URL(fileURLWithPath: paper.pdfPath)

                if paper.pdfPath.hasPrefix(home.path) {
                    report.alreadyPlaced += 1
                    claimed.insert(current.path)
                    continue
                }
                guard fm.fileExists(atPath: current.path) else {
                    report.missing += 1
                    store.clearPDFPath(paper.id)
                    continue
                }

                var dest = home.appendingPathComponent(current.lastPathComponent)
                var n = 2
                while fm.fileExists(atPath: dest.path) {
                    let stem = current.deletingPathExtension().lastPathComponent
                    dest = home.appendingPathComponent("\(stem)~\(n).pdf")
                    n += 1
                }
                do {
                    try fm.moveItem(at: current, to: dest)
                    store.setPDFPath(paper.id, dest.path)
                    claimed.insert(dest.path)
                    report.moved += 1
                } catch {
                    claimed.insert(current.path)
                }
            }
        }

        // Whatever is left in the old shared folder belongs to no record.
        if let leftovers = try? fm.contentsOfDirectory(at: Library.legacyPDFDir,
                                                      includingPropertiesForKeys: [.fileSizeKey]) {
            for file in leftovers where file.pathExtension.lowercased() == "pdf" {
                guard !claimed.contains(file.path) else { continue }
                report.orphans.append(file)
                report.orphanBytes += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) as? Int ?? 0
            }
        }

        if deleteOrphans {
            for file in report.orphans { try? fm.trashItem(at: file, resultingItemURL: nil) }
        }
        // Remove the old shared folder once it is empty.
        if let rest = try? fm.contentsOfDirectory(atPath: Library.legacyPDFDir.path), rest.isEmpty {
            try? fm.removeItem(at: Library.legacyPDFDir)
        }
        store.reloadPapers()
        PDFVault.invalidateAll()
        return report
    }

    /// Moves the whole library somewhere else — an external drive, a synced folder.
    /// Paths are stored relative to the root, so nothing inside needs rewriting.
    static func relocate(to newRoot: URL, store: Store) throws {
        let fm = FileManager.default
        let old = Library.root
        guard old.path != newRoot.path else { return }

        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        for item in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] {
            // The write-ahead log belongs to the open database and is rebuilt on next launch.
            guard !item.hasSuffix("-wal"), !item.hasSuffix("-shm") else { continue }
            let from = old.appendingPathComponent(item)
            let to = newRoot.appendingPathComponent(item)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.moveItem(at: from, to: to)
        }
        Library.setRoot(newRoot)
    }
}
