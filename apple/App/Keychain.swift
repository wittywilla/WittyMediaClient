import Foundation
import Security
import WittyKit

/// The sign-in, and the key of the server it belongs to. Keeping the two together here means that
/// rewriting the app's plain settings can't point the token at another server.
///
/// Only this app reads these: no access group, so not its Top Shelf extension either, and no
/// iCloud. "This device only" keeps them out of backups, so a restored device signs in again.
/// There's no older format to move from: no earlier version of this app was ever installed. An
/// item with another accessibility class gets this one the next time it's written.
enum Keychain {
    private static let service = "com.wittywilla.wittymediaclient"
    private static let tokenAccount = "session-token"
    private static let pinAccount = "session-pin"

    // On a Mac the modern keychain needs a signed app. An unsigned test build falls back to the
    // older file-based one, which works but may ask the person for permission.
    #if os(macOS)
    private static let kinds = [true, false]
    #else
    private static let kinds = [true]
    #endif

    private static func query(_ account: String, modern: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        #if os(macOS)
        if modern { q[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return q
    }

    private static func read(_ account: String) -> String {
        for modern in kinds {
            var q = query(account, modern: modern)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
                return String(data: data, encoding: .utf8) ?? ""
            }
        }
        return ""
    }

    private static func write(_ value: String, _ account: String) -> OSStatus {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = errSecSuccess
        for modern in kinds {
            let q = query(account, modern: modern)
            status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                let adding = q.merging(attributes) { _, new in new }
                status = SecItemAdd(adding as CFDictionary, nil)
            }
            if status != errSecMissingEntitlement { break }
        }
        return status
    }

    static var token: String { read(tokenAccount) }

    /// The key of the server the token was kept with. Empty for a server too old to have one.
    static var pin: String { read(pinAccount) }

    /// False if it couldn't be kept, in which case nothing is: a sign-in with no key beside it
    /// would be a token that could go anywhere. The code goes in the log, never the values.
    static func save(token: String, pin: String) -> Bool {
        let tokenStatus = write(token, tokenAccount)
        let pinStatus = tokenStatus == errSecSuccess ? write(pin, pinAccount) : tokenStatus
        if pinStatus == errSecSuccess { return true }
        ClientLog.shared.warn("keychain", "The sign-in couldn't be saved: \(pinStatus)")
        clear()
        return false
    }

    static func clear() {
        for account in [tokenAccount, pinAccount] {
            for modern in kinds {
                let status = SecItemDelete(query(account, modern: modern) as CFDictionary)
                // Asking a Mac's modern keychain with no entitlement fails too, and has nothing in it.
                if status != errSecSuccess, status != errSecItemNotFound, status != errSecMissingEntitlement {
                    ClientLog.shared.warn("keychain", "The sign-in couldn't be removed: \(status)")
                }
            }
        }
    }
}
