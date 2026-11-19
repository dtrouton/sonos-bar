// SonoBar/Services/PlexKeychain.swift

import Foundation
import Security

/// Reads and writes the Plex token to the macOS Keychain.
enum PlexKeychain {
    private static let service = "com.sonobar.plex"
    private static let account = "token"

    private struct SaveError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "Couldn’t save your Plex sign-in in Keychain (\(status))."
        }
    }

    /// Reads the stored Plex token, or nil if not set.
    static func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores the Plex token in the Keychain. Overwrites if exists.
    static func setToken(_ token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, newValue in newValue }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SaveError(status: status) }
    }

    /// Removes the Plex token from the Keychain.
    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
