import Foundation
import AppKit
import Security

/// Opening a URL hands control to whatever application claims its scheme. Every link Sieve
/// can open arrives from an external source — a search API's JSON, a DOI record, a `.bib`
/// file someone else exported — so a hostile or compromised response could otherwise ask
/// the app to launch `file:///`, `ssh://`, or a custom scheme registered by malware.
/// Nothing but plain web traffic is ever opened.
enum SafeLink {
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// Returns the URL only if it is ordinary web traffic with a real host.
    static func web(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return web(url)
    }

    static func web(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The only route by which Sieve opens anything in another application.
    @discardableResult
    static func open(_ string: String) -> Bool {
        guard let url = web(string) else { return false }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard let safe = web(url) else { return false }
        return NSWorkspace.shared.open(safe)
    }

    /// Builds the canonical link for a record, preferring its DOI.
    static func forPaper(url: String, doi: String) -> URL? {
        if !doi.isEmpty, let u = web("https://doi.org/\(doi)") { return u }
        return web(url)
    }
}

/// API keys are credentials. Stored in `UserDefaults` they sit in a world-readable plist in
/// the user's Library folder, where any process running as that user can read them. They
/// belong in the Keychain, which is encrypted at rest and access-controlled by the system.
///
/// Keys written by earlier versions are migrated on first read and then deleted from the
/// preferences file.
enum KeyStore {
    private static let service = "com.saikiran.Sieve"

    static func get(_ account: String) -> String {
        if let migrated = migrateIfNeeded(account) { return migrated }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = withUnsafeMutablePointer(to: &item) {
            SecItemCopyMatching(query as CFDictionary, $0)
        }
        query.removeAll()
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func set(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        // The key is only needed while the app is running, and never leaves this machine.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Moves a key written by an older build out of the preferences plist.
    private static func migrateIfNeeded(_ account: String) -> String? {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty else { return nil }
        set(legacy, for: account)
        defaults.removeObject(forKey: account)
        defaults.synchronize()
        return legacy
    }
}
