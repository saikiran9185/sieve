import Foundation

/// Opening a URL hands control to whatever application claims its scheme. Every link Sieve
/// can open arrives from an external source — a search API's JSON, a DOI record, a `.bib`
/// file someone else exported — so a hostile or compromised response could otherwise ask
/// the app to launch `file:///`, `ssh://`, or a custom scheme registered by malware.
/// Nothing but plain web traffic is ever opened.
///
/// The *decision* is here, in portable code, so every platform gets the same answer.
/// Actually handing a URL to the desktop is per-platform and lives in the app target.
public enum SafeLink {
    public static let allowedSchemes: Set<String> = ["http", "https"]

    /// Returns the URL only if it is ordinary web traffic with a real host.
    public static func web(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return web(url)
    }

    public static func web(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Builds the canonical link for a record, preferring its DOI.
    public static func forPaper(url: String, doi: String) -> URL? {
        if !doi.isEmpty, let u = web("https://doi.org/\(doi)") { return u }
        return web(url)
    }
}

// MARK: - Credentials

/// Where API keys are kept. The Keychain on macOS; on Windows this is the seam where a
/// DPAPI-backed store plugs in. The engine only ever asks for a key by name, so no
/// platform's credential API leaks into the provider code.
public protocol SecretStore: AnyObject, Sendable {
    func get(_ account: String) -> String
    func set(_ value: String, for account: String)
}

/// Keys live in memory only. This is the default so the engine is usable in tests and on a
/// platform whose real store is not written yet — never a silent fallback in the shipping
/// app, which installs its own store before any provider runs.
public final class EphemeralSecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func get(_ account: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return values[account] ?? ""
    }

    public func set(_ value: String, for account: String) {
        lock.lock(); defer { lock.unlock() }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { values.removeValue(forKey: account) } else { values[account] = trimmed }
    }
}

/// The engine's access point for credentials. The host app installs the platform store at
/// launch; everything underneath asks only this.
public enum Secrets {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _store: SecretStore = EphemeralSecretStore()

    public static var store: SecretStore {
        get { lock.lock(); defer { lock.unlock() }; return _store }
        set { lock.lock(); defer { lock.unlock() }; _store = newValue }
    }

    public static func get(_ account: String) -> String { store.get(account) }
    public static func set(_ value: String, for account: String) { store.set(value, for: account) }
}
