import Foundation
import SwiftUI

/// Marks the words from your criteria wherever they appear in an abstract.
///
/// Borrowed from Rayyan, where it is the single thing that speeds screening most: the
/// decision usually turns on two or three words, and finding them by eye in a 300-word
/// abstract is the slow part. Green for a term from the inclusion criteria, red for one from
/// the exclusion criteria — the judgement stays yours, but the evidence for it is visible.
enum CriteriaHighlight {

    /// Words too common to be worth marking. Highlighting "study" in a paper abstract makes
    /// the whole page green and tells you nothing.
    private static let stopWords: Set<String> = [
        "the", "and", "or", "not", "with", "without", "any", "all", "for", "from", "that",
        "this", "than", "then", "must", "should", "have", "has", "was", "were", "are", "is",
        "be", "been", "which", "when", "who", "whose", "into", "onto", "over", "under",
        "more", "less", "most", "least", "only", "also", "such", "some", "each", "per",
        "study", "studies", "paper", "papers", "article", "articles", "research", "based",
        "years", "year", "old", "older", "newer", "new", "min", "max", "related", "relation",
        "it", "its", "in", "on", "of", "to", "a", "an", "at", "by", "if", "as", "no"
    ]

    /// Pulls candidate terms out of a criteria field. A quoted phrase is kept whole.
    static func terms(from criteria: String) -> [String] {
        guard !criteria.isEmpty else { return [] }
        var out: [String] = []
        var rest = criteria

        // "peer reviewed" in quotes means the phrase, not the two words.
        let quoted = try? NSRegularExpression(pattern: "\"([^\"]{2,60})\"")
        if let quoted {
            let ns = rest as NSString
            for m in quoted.matches(in: rest, range: NSRange(location: 0, length: ns.length)).reversed() {
                let phrase = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if phrase.count > 2 { out.append(phrase) }
                rest = (rest as NSString).replacingCharacters(in: m.range, with: " ")
            }
        }

        for token in rest.components(separatedBy: CharacterSet(charactersIn: " ,;·•\n\t()[]/")) {
            let word = token.trimmingCharacters(in: CharacterSet(charactersIn: " .-—"))
            guard word.count >= 4, !stopWords.contains(word.lowercased()),
                  word.rangeOfCharacter(from: .letters) != nil else { continue }
            out.append(word)
        }
        // Longest first, so "user study" wins over "study" when both are present.
        return Array(Set(out)).sorted { $0.count > $1.count }
    }

    /// Builds the abstract with matched terms tinted. Matching is on word stems, so
    /// "packaging" is found by the criterion "package".
    static func attributed(_ text: String, include: String, exclude: String,
                           includeColor: Color, excludeColor: Color) -> AttributedString {
        var attributed = AttributedString(text)
        guard !text.isEmpty else { return attributed }

        let includeTerms = terms(from: include)
        let excludeTerms = terms(from: exclude)
        guard !includeTerms.isEmpty || !excludeTerms.isEmpty else { return attributed }

        // Exclusion is applied last so a word in both criteria shows as the stricter one.
        for (list, color) in [(includeTerms, includeColor), (excludeTerms, excludeColor)] {
            for term in list {
                let stem = stemOf(term)
                guard stem.count >= 4 else { continue }
                var searchFrom = attributed.startIndex
                while searchFrom < attributed.endIndex,
                      let found = attributed[searchFrom...].range(of: stem, options: .caseInsensitive) {
                    // Extend the mark to the whole word, so "packag" tints "packaging".
                    var end = found.upperBound
                    while end < attributed.endIndex,
                          let ch = attributed.characters[end] as Character?, ch.isLetter {
                        end = attributed.index(afterCharacter: end)
                    }
                    let range = found.lowerBound..<end
                    attributed[range].backgroundColor = color.opacity(0.22)
                    attributed[range].foregroundColor = color
                    searchFrom = end < attributed.endIndex ? end : attributed.endIndex
                }
            }
        }
        return attributed
    }

    /// A crude stem: drop a plural or gerund ending so one criterion matches its variants.
    private static func stemOf(_ term: String) -> String {
        var t = term.lowercased()
        for suffix in ["ing", "ies", "es", "s"] where t.count > 5 && t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count))
            break
        }
        return t
    }

    /// How many criteria words actually appear — shown beside the abstract so a record with
    /// no match at all is obvious before you read a word of it.
    static func matchCount(_ text: String, criteria: String) -> Int {
        let lower = text.lowercased()
        return terms(from: criteria).filter { lower.contains(stemOf($0)) }.count
    }
}
