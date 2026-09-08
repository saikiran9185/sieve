import Foundation
import SwiftUI

/// What the assistant was asked, what it answered, and what the researcher decided about it.
///
/// A flag saying "this came from AI" is enough to draw a badge. It cannot answer the question
/// a supervisor, a peer reviewer or a journal will actually ask — *which* claims came from a
/// model, and did a human check them against the source? That question is why this exists.
///
/// Rows are never edited except to record the human's verdict, and never deleted while the
/// review lives. The point of a trail is that it cannot be tidied up afterwards.
struct AIEvent: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var at: Date
    var kind: Kind
    var model: String
    var subjectKind: String        // paper | evidence | cell | project
    var subjectId: Int
    var columnId: Int
    var asked: String
    var said: String
    var confidence: String
    var outcome: Outcome
    var outcomeAt: Date?
    var humanNote: String

    enum Kind: String, CaseIterable, Identifiable {
        case screen, suggestTag, draftCell, askCorpus, buildQueries
        var id: String { rawValue }

        var label: String {
            switch self {
            case .screen: return "Screening recommendation"
            case .suggestTag: return "Category suggestion"
            case .draftCell: return "Matrix cell drafted"
            case .askCorpus: return "Question asked of the corpus"
            case .buildQueries: return "Search strings suggested"
            }
        }

        /// Whether a human verdict is required before the review can be called checked.
        /// A suggested search string shapes nothing that ends up in the write-up; a drafted
        /// extraction does.
        var needsAdjudication: Bool {
            switch self {
            case .screen, .suggestTag, .draftCell: return true
            case .askCorpus, .buildQueries: return false
            }
        }

        var icon: String {
            switch self {
            case .screen: return "checklist"
            case .suggestTag: return "tag"
            case .draftCell: return "tablecells"
            case .askCorpus: return "text.bubble"
            case .buildQueries: return "magnifyingglass"
            }
        }
    }

    enum Outcome: String, CaseIterable, Identifiable {
        case pending, accepted, rejected, edited, unused
        var id: String { rawValue }

        var label: String {
            switch self {
            case .pending: return "Not yet checked"
            case .accepted: return "Accepted as given"
            case .rejected: return "Rejected"
            case .edited: return "Accepted after editing"
            case .unused: return "Read, not used"
            }
        }

        var color: Color {
            switch self {
            case .pending: return Palette.amber
            case .accepted: return Palette.accent
            case .rejected: return Palette.rose
            case .edited: return Palette.emerald
            case .unused: return Palette.slate
            }
        }

        var icon: String {
            switch self {
            case .pending: return "questionmark.circle"
            case .accepted: return "checkmark.circle"
            case .rejected: return "xmark.circle"
            case .edited: return "pencil.circle"
            case .unused: return "minus.circle"
            }
        }
    }

    /// A one-line account for the disclosure report.
    @MainActor
    func line(store: Store) -> String {
        var subject = ""
        switch subjectKind {
        case "paper": subject = store.paper(subjectId).map { "\($0.citeKey) — \($0.title.prefix(60))" } ?? "a record"
        case "evidence": subject = store.evidence(subjectId).map { "a highlight: \($0.quote.prefix(50))" } ?? "a highlight"
        case "cell":
            let p = store.paper(subjectId)?.citeKey ?? "?"
            let c = store.columns.first { $0.id == columnId }?.name ?? "a column"
            subject = "\(p) · \(c)"
        default: subject = "the review"
        }
        return "\(at.formatted(date: .abbreviated, time: .shortened)) · \(kind.label) · \(subject) · \(outcome.label)"
    }
}
