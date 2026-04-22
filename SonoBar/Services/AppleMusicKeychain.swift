// SonoBar/Services/AppleMusicKeychain.swift

import Foundation
import Security
import SonoBarKit

/// Reads and writes Apple Music credentials (sn + accountToken) to the macOS Keychain.
/// Mirrors the PlexKeychain / AudibleKeychain patterns for consistency.
enum AppleMusicKeychain {
    private static let service = "com.sonobar.appleMusic"
    private static let account = "credentials"

    /// Reads the stored Apple Music credentials, or nil if not set.
    static func getCredentials() -> AppleMusicCredentials? {
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
        return try? JSONDecoder().decode(Stored.self, from: data).asCredentials
    }

    /// Stores the credentials in the Keychain. Overwrites if already present.
    static func setCredentials(_ creds: AppleMusicCredentials) {
        deleteCredentials()
        guard let data = try? JSONEncoder().encode(Stored(from: creds)) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Removes the credentials from the Keychain.
    static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// JSON-encodable shape paired with `AppleMusicCredentials`.
    /// `AppleMusicCredentials` isn't `Codable` — keep encoding concerns in the keychain adapter.
    private struct Stored: Codable {
        let sn: Int
        let accountToken: String

        init(from creds: AppleMusicCredentials) {
            self.sn = creds.sn
            self.accountToken = creds.accountToken
        }

        var asCredentials: AppleMusicCredentials {
            AppleMusicCredentials(sn: sn, accountToken: accountToken)
        }
    }
}
