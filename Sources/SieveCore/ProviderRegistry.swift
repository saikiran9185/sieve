import Foundation

/// Every academic database Sieve can query directly.
///
/// The concrete provider types stay internal to `SieveCore` deliberately: the host app
/// asks for the list, never for a named provider. Adding a fifteenth database is then a
/// one-line change here that every platform's interface picks up for free.
public enum ProviderRegistry {
    public static let all: [any SearchProvider] = [
        OpenAlexProvider(), CrossrefProvider(), EuropePMCProvider(), PubMedProvider(),
        COREProvider(), OpenAIREProvider(), ArxivProvider(), DOAJProvider(), PLOSProvider(),
        SemanticScholarProvider(), IEEEProvider(), SpringerProvider(),
        ElsevierProvider(), LensProvider()
    ]

    /// The keyless databases, which are the ones a fresh install can use immediately.
    public static var defaultEnabledNames: Set<String> {
        Set(all.filter { !$0.needsKey }.map(\.name))
    }

    public static func named(_ name: String) -> (any SearchProvider)? {
        all.first { $0.name == name }
    }
}

/// OpenAlex ships abstracts as an inverted index — a word-to-positions map rather than
/// running text — so reconstructing one is needed both when searching and when importing
/// a record fetched by DOI. It is plain parsing, so it lives out here rather than inside
/// the provider, and both paths share it.
public enum OpenAlex {
    public static func invertedAbstract(_ any: Any?) -> String {
        guard let inv = any as? [String: [Int]] else { return "" }
        var words: [(Int, String)] = []
        for (word, positions) in inv { for p in positions { words.append((p, word)) } }
        return words.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: " ")
    }
}
