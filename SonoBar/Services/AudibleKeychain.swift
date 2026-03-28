// SonoBar/Services/AudibleKeychain.swift

import Foundation
import Security

/// Reads and writes Audible credentials to the macOS Keychain.
/// All credentials are stored as a single JSON blob to avoid multiple
/// keychain authorization prompts at startup.
enum AudibleKeychain {
    private static let service = "com.sonobar.audible"
    private static let account = "credentials"

    // MARK: - Credential Bundle

    private struct Credentials: Codable {
        var accessToken: String
        var refreshToken: String
        var adpToken: String
        var privateKeyPEM: String
        var deviceSerial: String
    }

    // MARK: - Public Getters

    static func getAccessToken() -> String? { load()?.accessToken }
    static func getRefreshToken() -> String? { load()?.refreshToken }
    static func getAdpToken() -> String? { load()?.adpToken }
    static func getPrivateKeyPEM() -> String? { load()?.privateKeyPEM }
    static func getDeviceSerial() -> String? { load()?.deviceSerial }

    // MARK: - Public Setters

    static func setAccessToken(_ token: String) {
        update { $0.accessToken = token }
    }

    static func setRefreshToken(_ token: String) {
        update { $0.refreshToken = token }
    }

    static func setAdpToken(_ token: String) {
        update { $0.adpToken = token }
    }

    static func setPrivateKeyPEM(_ key: String) {
        update { $0.privateKeyPEM = key }
    }

    static func setDeviceSerial(_ serial: String) {
        update { $0.deviceSerial = serial }
    }

    /// Stores all credentials at once (used during initial registration).
    static func setAll(
        accessToken: String,
        refreshToken: String,
        adpToken: String,
        privateKeyPEM: String,
        deviceSerial: String
    ) {
        let creds = Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            adpToken: adpToken,
            privateKeyPEM: privateKeyPEM,
            deviceSerial: deviceSerial
        )
        save(creds)
    }

    // MARK: - Delete All

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        // Also clean up old per-field items from previous versions
        for oldAccount in ["accessToken", "refreshToken", "adpToken", "privateKey", "deviceSerial"] {
            let oldQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: oldAccount,
            ]
            SecItemDelete(oldQuery as CFDictionary)
        }
    }

    // MARK: - Private Helpers

    private static func load() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            // Try migrating from old per-field storage
            return migrateFromLegacy()
        }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    private static func save(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }

        // Delete existing, then add new
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func update(_ mutate: (inout Credentials) -> Void) {
        var creds = load() ?? Credentials(
            accessToken: "", refreshToken: "", adpToken: "",
            privateKeyPEM: "", deviceSerial: ""
        )
        mutate(&creds)
        save(creds)
    }

    /// One-time migration from old per-field keychain items to single blob.
    private static func migrateFromLegacy() -> Credentials? {
        func getLegacy(_ acct: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: acct,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        guard let accessToken = getLegacy("accessToken"),
              let refreshToken = getLegacy("refreshToken"),
              let adpToken = getLegacy("adpToken"),
              let privateKey = getLegacy("privateKey") else {
            return nil
        }

        let creds = Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            adpToken: adpToken,
            privateKeyPEM: privateKey,
            deviceSerial: getLegacy("deviceSerial") ?? ""
        )

        // Save as single blob and delete old items
        save(creds)
        for oldAccount in ["accessToken", "refreshToken", "adpToken", "privateKey", "deviceSerial"] {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: oldAccount,
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }

        #if DEBUG
        print("[AudibleKeychain] Migrated legacy per-field items to single blob")
        #endif

        return creds
    }
}
