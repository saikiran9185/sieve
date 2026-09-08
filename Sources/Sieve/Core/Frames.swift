import Foundation
import SwiftUI

/// A framework — SWOT, a journey map, an empathy map — is a grid whose cells cite evidence.
///
/// The important design decision: a frame is a **view over the same evidence**, not a
/// separate kind of data. A quote pulled from an interview transcript can sit in a journey
/// map, an empathy map and the literature matrix at once, and in all three it still points
/// back to the same source, page and timestamp. That is what separates this from a
/// whiteboard, where a sticky note is just text somebody typed.
struct Frame: Identifiable, Hashable {
    var id: Int
    var projectId: Int
    var name: String
    var kind: String
    var detail: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var template: FrameTemplate? { FrameTemplate(rawValue: kind) }
    var icon: String { template?.icon ?? "square.grid.3x3" }
}

/// One row or column of a frame. A row can point at a source, which is how "one row per
/// participant" or "one row per competitor" works without inventing a second table.
struct FrameAxis: Identifiable, Hashable {
    var id: Int
    var frameId: Int
    var isRow: Bool
    var name: String
    var detail: String = ""
    var sortOrder: Int = 0
    var colorHex: String = ""
    var sourceId: Int?

    var color: Color? { colorHex.isEmpty ? nil : .readable(colorHex) }
}

struct FrameCell: Hashable {
    var rowId: Int
    var colId: Int
    var value: String = ""
    var evidenceIds: [Int] = []
    var aiGenerated: Bool = false
}

/// The methods Sieve can set up for you. Each is a starting grid, not a cage — rows and
/// columns are editable the moment it is created.
enum FrameTemplate: String, CaseIterable, Identifiable {
    case swot, journey, empathy, competitive, assumptions, researchPlan, affinity, twoByTwo, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .swot: return "SWOT"
        case .journey: return "User journey"
        case .empathy: return "Empathy map"
        case .competitive: return "Competitive analysis"
        case .assumptions: return "Assumptions and risks"
        case .researchPlan: return "Research plan"
        case .affinity: return "Affinity themes"
        case .twoByTwo: return "Prioritisation 2×2"
        case .custom: return "Blank grid"
        }
    }

    var blurb: String {
        switch self {
        case .swot: return "Strengths, weaknesses, opportunities, threats — each one made to cite what it rests on."
        case .journey: return "Stages across the top of a user's experience, with what they do, think, feel and struggle with."
        case .empathy: return "Says, thinks, does, feels — separating what was observed from what you inferred."
        case .competitive: return "One row per product you are up against, compared on the same dimensions."
        case .assumptions: return "What you are taking for granted, the evidence for and against, and how you would test it."
        case .researchPlan: return "Your research questions, the method for each, and what you actually learned."
        case .affinity: return "Themes down the side, with the observations that built each one."
        case .twoByTwo: return "Impact against effort, or any two axes, with each item justified."
        case .custom: return "Rows and columns you define entirely."
        }
    }

    var icon: String {
        switch self {
        case .swot: return "square.split.2x2"
        case .journey: return "arrow.right.to.line"
        case .empathy: return "brain.head.profile"
        case .competitive: return "chart.bar.doc.horizontal"
        case .assumptions: return "exclamationmark.triangle"
        case .researchPlan: return "list.clipboard"
        case .affinity: return "circle.grid.3x3"
        case .twoByTwo: return "squareshape.split.2x2"
        case .custom: return "square.grid.3x3"
        }
    }

    /// Whether rows are added by the researcher as work proceeds (participants, competitors,
    /// assumptions) rather than fixed by the method (SWOT quadrants, empathy quadrants).
    var rowsAreOpen: Bool {
        switch self {
        case .swot, .empathy, .journey: return false
        default: return true
        }
    }

    var rowNoun: String {
        switch self {
        case .competitive: return "product"
        case .assumptions: return "assumption"
        case .researchPlan: return "research question"
        case .affinity: return "theme"
        case .twoByTwo: return "item"
        default: return "row"
        }
    }

    /// (rows, columns) the frame starts with.
    var starting: (rows: [(String, String)], cols: [(String, String)]) {
        switch self {
        case .swot:
            return ([("Strengths", "Working in your favour, and internal to you."),
                     ("Weaknesses", "Working against you, and within your control."),
                     ("Opportunities", "Outside conditions you could turn to advantage."),
                     ("Threats", "Outside conditions that could go against you.")],
                    [("What we found", "State it plainly."),
                     ("What it rests on", "Cite the evidence. A SWOT with nothing behind it is a guess."),
                     ("So what", "What this should change about the decision.")])
        case .journey:
            return ([("Before — trigger", "What sends them looking in the first place."),
                     ("Discover", "Finding out the thing exists."),
                     ("Decide", "Weighing it up against alternatives."),
                     ("First use", "The first real attempt."),
                     ("Habitual use", "Once it is part of their routine."),
                     ("Trouble", "When something goes wrong."),
                     ("Leave or renew", "Why they stay or stop.")],
                    [("Doing", "The observable action."),
                     ("Thinking", "What they said they were thinking."),
                     ("Feeling", "Their emotional state, in their words where possible."),
                     ("Pain points", "Where it breaks down."),
                     ("Opportunity", "What a design could do here.")])
        case .empathy:
            return ([("Says", "Direct quotes. Verbatim only."),
                     ("Thinks", "What they appear to believe but did not say aloud — an inference."),
                     ("Does", "Observed behaviour."),
                     ("Feels", "Emotional state, evidenced by what they said or did."),
                     ("Pains", "Frustrations, obstacles, fears."),
                     ("Gains", "What they want, and how they measure success.")],
                    [("Observed", "What you actually saw or heard."),
                     ("Inferred", "What you concluded from it — mark it as interpretation."),
                     ("Evidence", "The quote or clip it came from.")])
        case .competitive:
            return ([], [("What it does well", ""),
                         ("Where it falls short", ""),
                         ("Who it is for", ""),
                         ("What we would do differently", ""),
                         ("Evidence", "Screenshots, reviews, your own trial notes.")])
        case .assumptions:
            return ([], [("Why we believe it", "Where this assumption came from."),
                         ("Evidence for", ""),
                         ("Evidence against", ""),
                         ("How we would test it", ""),
                         ("Risk if wrong", "What breaks if this is false.")])
        case .researchPlan:
            return ([], [("Why it matters", "What decision hangs on the answer."),
                         ("Method", "Interview, diary study, usability test, survey."),
                         ("Who", "How many people, recruited how."),
                         ("What would count as an answer", "Decide before you collect anything."),
                         ("What we learned", "Filled in afterwards.")])
        case .affinity:
            return ([], [("What the theme says", ""),
                         ("Observations behind it", "Cite every one."),
                         ("How many people", "A theme from one person is not yet a theme."),
                         ("Counter-evidence", "What did not fit.")])
        case .twoByTwo:
            return ([], [("Impact", "High or low, and why."),
                         ("Effort", "High or low, and why."),
                         ("Evidence", ""),
                         ("Decision", "Do now, do later, or drop.")])
        case .custom:
            return ([], [("Column 1", "")])
        }
    }

    /// Which method blocks this framework belongs to, so the Method screen can suggest it.
    static func suggested(for block: MethodBlock) -> [FrameTemplate] {
        switch block {
        case .compare: return [.competitive, .twoByTwo]
        case .cluster: return [.affinity, .empathy]
        case .synthesize: return [.swot, .journey, .affinity]
        case .validate: return [.assumptions]
        case .search, .screen: return [.researchPlan]
        default: return []
        }
    }
}
