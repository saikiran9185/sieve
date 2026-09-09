import Foundation
import CoreGraphics

/// Where you were in a document when you last closed it.
///
/// Reading a paper is not one sitting. Losing the page — and the zoom you had settled on —
/// every time the app relaunches or you glance at another paper is the difference between
/// picking a paper back up and starting it again.
struct ReadingPosition: Codable, Equatable {
    var page: Int = 0
    var scale: Double = 0          // 0 means "no zoom chosen yet, fit the page"
    var offsetX: Double = 0
    var offsetY: Double = 0

    var hasScale: Bool { scale > 0.05 }
}

enum ReadingMemory {
    private static let d = UserDefaults.standard

    private static func key(paper: Int) -> String { "sieve.reading.\(paper)" }

    static func position(paper: Int) -> ReadingPosition? {
        guard let data = d.data(forKey: key(paper: paper)) else { return nil }
        return try? JSONDecoder().decode(ReadingPosition.self, from: data)
    }

    static func save(_ p: ReadingPosition, paper: Int) {
        guard let data = try? JSONEncoder().encode(p) else { return }
        d.set(data, forKey: key(paper: paper))
    }

    static func forget(paper: Int) { d.removeObject(forKey: key(paper: paper)) }

    /// Called on the way out. Quitting is the case where "it remembered while the app was
    /// open but forgot when I reopened it" comes from, so the last write is forced to disk
    /// rather than left to the next flush.
    static func flush() { d.synchronize() }

    // MARK: Where the app itself was

    /// The paper you had open, per review, so reopening Sieve lands you back in the document
    /// rather than on a dashboard you then have to navigate out of.
    static func lastPaper(project: Int) -> Int? {
        let v = d.integer(forKey: "sieve.lastPaper.\(project)")
        return v > 0 ? v : nil
    }

    static func setLastPaper(_ id: Int?, project: Int) {
        d.set(id ?? 0, forKey: "sieve.lastPaper.\(project)")
    }

    static var lastSection: String? {
        get { d.string(forKey: "sieve.lastSection") }
        set { d.set(newValue, forKey: "sieve.lastSection") }
    }
}
