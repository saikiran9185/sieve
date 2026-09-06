import Foundation
import PDFKit

/// The evidence that a full text was actually obtained.
///
/// PRISMA distinguishes reports *sought* from reports *retrieved*, and the difference has to
/// be a fact about the disk, not an intention. A record can carry a `pdf_url` it never
/// downloaded, or point at a file that has since been deleted, moved or replaced with a
/// publisher's HTML error page saved under a `.pdf` name. None of those is a retrieved report.
///
/// Verification is cached because it answers a question asked once per row per redraw, and
/// hitting the file system inside a SwiftUI body is how a list of 150 papers starts to stutter.
enum PDFVault {
    struct Proof: Equatable {
        var exists = false
        var isPDF = false
        var bytes = 0
        var pages = 0
        var checkedAt = Date()

        /// A report counts as retrieved only when a readable PDF is on disk.
        var retrieved: Bool { exists && isPDF && pages > 0 }

        var sizeText: String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    private static var cache: [String: Proof] = [:]
    private static let lock = NSLock()

    /// Cheap answer for view bodies. Verifies once, then reuses the result until invalidated.
    static func proof(for path: String) -> Proof {
        guard !path.isEmpty else { return Proof() }
        lock.lock()
        if let hit = cache[path] { lock.unlock(); return hit }
        lock.unlock()

        let fresh = verify(path)
        lock.lock(); cache[path] = fresh; lock.unlock()
        return fresh
    }

    /// Reads the file for real. A PDF must exist, start with `%PDF-`, and open with at least
    /// one page — the header alone is not enough, since a truncated download keeps it.
    static func verify(_ path: String) -> Proof {
        var p = Proof()
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return p }
        p.exists = true
        p.bytes = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) as? Int ?? 0

        guard let handle = FileHandle(forReadingAtPath: path) else { return p }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 5)) ?? Data()
        guard header == Data("%PDF-".utf8) else { return p }
        p.isPDF = true

        // PDFKit is the same parser the reader uses, so if it cannot open the file the app
        // cannot show it either, whatever the header claims.
        if let doc = PDFDocument(url: URL(fileURLWithPath: path)) { p.pages = doc.pageCount }
        return p
    }

    static func invalidate(_ path: String) {
        guard !path.isEmpty else { return }
        lock.lock(); cache.removeValue(forKey: path); lock.unlock()
    }

    static func invalidateAll() {
        lock.lock(); cache.removeAll(); lock.unlock()
    }
}
