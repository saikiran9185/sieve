import Foundation
import AppKit
import Security
import SieveCore

/// The scheme allow-list and every URL check now live in `SieveCore.SafeLink`, so macOS and
/// Windows make the same decision about what counts as a safe link. What stays here is the
/// only part that is genuinely per-platform: actually handing a URL to the desktop.
extension SafeLink {
    /// The only route by which Sieve opens anything in another application.
    @discardableResult
    public static func open(_ string: String) -> Bool {
        guard let url = web(string) else { return false }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    public static func open(_ url: URL) -> Bool {
        guard let safe = web(url) else { return false }
        return NSWorkspace.shared.open(safe)
    }
}

/// API keys are credentials. Stored in `UserDefaults` they sit in a world-readable plist in
/// the user's Library folder, where any process running as that user can read them. They
/// belong in the Keychain, which is encrypted at rest and access-controlled by the system.
///
/// Keys written by earlier versions are migrated on first read and then deleted from the
/// preferences file.
///
/// This is the macOS implementation of `SieveCore.SecretStore`; `App` installs it at launch.
final class KeychainStore: SecretStore, @unchecked Sendable {
    static let shared = KeychainStore()
    private static let service = "com.saikiran.Sieve"

    func get(_ account: String) -> String {
        if let migrated = migrateIfNeeded(account) { return migrated }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
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

    func set(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
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
    private func migrateIfNeeded(_ account: String) -> String? {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty else { return nil }
        set(legacy, for: account)
        defaults.removeObject(forKey: account)
        defaults.synchronize()
        return legacy
    }
}

/// Kept so existing call sites read unchanged; the storage is the Keychain either way.
enum KeyStore {
    static func get(_ account: String) -> String { KeychainStore.shared.get(account) }
    static func set(_ value: String, for account: String) { KeychainStore.shared.set(value, for: account) }
}
