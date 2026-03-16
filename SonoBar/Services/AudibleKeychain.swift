// SonoBar/Services/AudibleKeychain.swift

import Foundation
import Security

/// Reads and writes Audible credentials to the macOS Keychain.
enum AudibleKeychain {
    private static let service = "com.sonobar.audible"

    // MARK: - Access Token

    static func getAccessToken() -> String? {
        get(account: "accessToken")
    }

    static func setAccessToken(_ token: String) {
        set(token, account: "accessToken")
    }

    // MARK: - Refresh Token

    static func getRefreshToken() -> String? {
        get(account: "refreshToken")
    }

    static func setRefreshToken(_ token: String) {
        set(token, account: "refreshToken")
    }

    // MARK: - ADP Token

    static func getAdpToken() -> String? {
        get(account: "adpToken")
    }

    static func setAdpToken(_ token: String) {
        set(token, account: "adpToken")
    }

    // MARK: - Private Key PEM

    static func getPrivateKeyPEM() -> String? {
        get(account: "privateKey")
    }

    static func setPrivateKeyPEM(_ key: String) {
        set(key, account: "privateKey")
    }

    // MARK: - Device Serial

    static func getDeviceSerial() -> String? {
        get(account: "deviceSerial")
    }

    static func setDeviceSerial(_ serial: String) {
        set(serial, account: "deviceSerial")
    }

    // MARK: - Delete All

    /// Clears all stored Audible credentials from the Keychain.
    static func deleteAll() {
        for account in ["accessToken", "refreshToken", "adpToken", "privateKey", "deviceSerial"] {
            delete(account: account)
        }
    }

    // MARK: - Private Helpers

    private static func get(account: String) -> String? {
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

    private static func set(_ value: String, account: String) {
        delete(account: account)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
