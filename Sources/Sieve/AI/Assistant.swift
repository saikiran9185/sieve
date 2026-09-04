import Foundation
import SwiftUI

/// Bridge to the `claude` CLI. The assistant is deliberately kept to the edges of the
/// workflow: it proposes, you decide. Everything it writes is stamped as AI-generated
/// so an AI sentence can never quietly become evidence in your review.
@MainActor
final class Assistant: ObservableObject {
    @Published var busy = false
    @Published var lastOutput = ""
    @Published var lastError = ""

    static var binaryPath: String? {
        let candidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSHomeDirectory() + "/.claude/local/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { binaryPath != nil }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sieve.ai") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sieve.ai"); objectWillChange.send() }
    }

    // MARK: - Process plumbing

    private func run(prompt: String, system: String) async throws -> String {
        guard let bin = Self.binaryPath else {
            throw NSError(domain: "Sieve", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The `claude` command-line tool wasn't found. Install Claude Code, or turn the assistant off in Settings."])
        }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                p.arguments = ["-p", prompt, "--append-system-prompt", system]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin:" + NSHomeDirectory() + "/.local/bin"
                p.environment = env
                let out = Pipe(), err = Pipe()
                p.standardOutput = out; p.standardError = err
                do { try p.run() } catch { cont.resume(throwing: error); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                if p.terminationStatus != 0 && text.isEmpty {
                    let e = String(data: errData, encoding: .utf8) ?? "claude exited with \(p.terminationStatus)"
                    cont.resume(throwing: NSError(domain: "Sieve", code: 2,
                                                  userInfo: [NSLocalizedDescriptionKey: e]))
                } else {
                    cont.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    private static let systemPrompt = """
    You are assisting with an academic systematic literature review inside a desktop tool \
    called Sieve. Be terse and factual. Never invent findings, citations, numbers or quotes: \
    if the supplied text does not support an answer, say so plainly. When asked for JSON, \
    reply with the raw JSON object only — no prose, no markdown fences.
    """

    private func json(_ text: String) -> [String: Any]? {
        var t = text
        if let r = t.range(of: "```") {
            t = String(t[r.upperBound...])
            if t.hasPrefix("json") { t.removeFirst(4) }
            if let end = t.range(of: "```") { t = String(t[..<end.lowerBound]) }
        }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") else { return nil }
        let slice = String(t[start...end])
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
    }

    // MARK: - 1. Suggest a category for a highlight

    struct TagSuggestion { var tagName: String; var note: String; var confidence: String }

    func suggestTag(quote: String, tags: [Tag], question: String) async -> TagSuggestion? {
        busy = true; defer { busy = false }
        let list = tags.map { "- \($0.name): \($0.detail)" }.joined(separator: "\n")
        let prompt = """
        Review question: \(question.isEmpty ? "(not stated)" : question)

        Available categories:
        \(list)

        Highlighted passage from a paper:
        \"\"\"
        \(quote.prefix(2000))
        \"\"\"

        Pick the single best-fitting category name from the list, and write a one-sentence \
        note (max 20 words) saying what this passage contributes to the review.
        Reply as JSON: {"tag": "...", "note": "...", "confidence": "high|medium|low"}
        """
        do {
            let out = try await run(prompt: prompt, system: Self.systemPrompt)
            guard let j = json(out) else { lastError = "Unexpected reply"; return nil }
            return TagSuggestion(tagName: j["tag"] as? String ?? "",
                                 note: j["note"] as? String ?? "",
                                 confidence: j["confidence"] as? String ?? "low")
        } catch { lastError = error.localizedDescription; return nil }
    }

    // MARK: - 2. Screen an abstract against the criteria

    struct ScreenVerdict { var include: Bool; var reason: String; var confidence: String }

    func screen(paper: Paper, inclusion: String, exclusion: String, question: String) async -> ScreenVerdict? {
        busy = true; defer { busy = false }
        let prompt = """
        Review question: \(question.isEmpty ? "(not stated)" : question)

        Inclusion criteria:
        \(inclusion.isEmpty ? "(none written yet)" : inclusion)

        Exclusion criteria:
        \(exclusion.isEmpty ? "(none written yet)" : exclusion)

        Record under screening:
        Title: \(paper.title)
        Authors: \(paper.authorLine)
        Year: \(paper.year.map(String.init) ?? "unknown")
        Venue: \(paper.venue)
        Abstract: \(paper.abstract.isEmpty ? "(no abstract available)" : String(paper.abstract.prefix(3000)))

        Judge this record against the criteria only. If the abstract is missing or too thin \
        to judge, recommend including it so a human can look at the full text.
        Reply as JSON: {"include": true|false, "reason": "one short sentence", "confidence": "high|medium|low"}
        """
        do {
            let out = try await run(prompt: prompt, system: Self.systemPrompt)
            guard let j = json(out) else { lastError = "Unexpected reply"; return nil }
            return ScreenVerdict(include: j["include"] as? Bool ?? true,
                                 reason: j["reason"] as? String ?? "",
                                 confidence: j["confidence"] as? String ?? "low")
        } catch { lastError = error.localizedDescription; return nil }
    }

    // MARK: - 3. Draft a matrix cell from this paper's own highlights

    func draftCell(column: MatrixColumn, paper: Paper, evidence: [Evidence], tags: [Tag]) async -> String? {
        busy = true; defer { busy = false }
        let ev = evidence.prefix(30).map { e -> String in
            let names = e.tagIds.compactMap { id in tags.first { $0.id == id }?.name }.joined(separator: ", ")
            return "[p.\(e.page + 1)\(names.isEmpty ? "" : " · \(names)")] \(e.quote)\(e.note.isEmpty ? "" : " — my note: \(e.note)")"
        }.joined(separator: "\n\n")

        let prompt = """
        Paper: \(paper.title) — \(paper.authorLine), \(paper.year.map(String.init) ?? "n.d.")
        Abstract: \(paper.abstract.prefix(1500))

        My highlights from this paper:
        \(ev.isEmpty ? "(none yet)" : ev)

        Matrix column: "\(column.name)"
        What this column asks for: \(column.prompt.isEmpty ? column.name : column.prompt)

        Write the cell content for this column: 1–3 sentences, plain text, no preamble. \
        Base it on the highlights and abstract above and nothing else. Where a highlight \
        supports the statement, cite its page like (p.4). If there isn't enough material, \
        reply exactly: NOT ENOUGH EVIDENCE
        """
        do {
            let out = try await run(prompt: prompt, system: Self.systemPrompt)
            return out.replacingOccurrences(of: "\n\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { lastError = error.localizedDescription; return nil }
    }

    // MARK: - 4. Ask a question across every highlight in the review

    func askCorpus(question: String, evidence: [Evidence], papers: [Paper], tags: [Tag]) async -> String? {
        busy = true; defer { busy = false }
        let byPaper = Dictionary(grouping: evidence, by: \.paperId)
        var blocks: [String] = []
        for (pid, items) in byPaper {
            guard let p = papers.first(where: { $0.id == pid }) else { continue }
            let quotes = items.prefix(12).map { "  [p.\($0.page + 1)] \($0.quote.prefix(400))" }.joined(separator: "\n")
            blocks.append("### \(p.citeKey) — \(p.title) (\(p.authorLine), \(p.year.map(String.init) ?? "n.d."))\n\(quotes)")
        }
        let corpus = blocks.joined(separator: "\n\n").prefix(60_000)
        let prompt = """
        Below are my highlights from the papers in my review, grouped by paper.

        \(corpus)

        Question: \(question)

        Answer using only these highlights. Cite every claim with the paper's key and page, \
        like (smith2021, p.4). Where papers disagree, say so explicitly. If the highlights \
        do not answer the question, say which papers you would need to read more of.
        """
        do { return try await run(prompt: prompt, system: Self.systemPrompt) }
        catch { lastError = error.localizedDescription; return nil }
    }

    // MARK: - 5. Turn a review question into search strings per database

    func buildQueries(question: String) async -> String? {
        busy = true; defer { busy = false }
        let prompt = """
        My review question: \(question)

        Write 4 to 6 alternative search strings for academic databases (OpenAlex, Crossref, \
        Semantic Scholar, Europe PMC, arXiv, DOAJ). Vary synonyms and specificity — one broad, \
        one narrow, the rest in between. One per line, no numbering, no explanation.
        """
        do { return try await run(prompt: prompt, system: Self.systemPrompt) }
        catch { lastError = error.localizedDescription; return nil }
    }
}
