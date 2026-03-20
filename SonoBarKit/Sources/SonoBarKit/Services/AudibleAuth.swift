// SonoBarKit/Sources/SonoBarKit/Services/AudibleAuth.swift
import Foundation
import CryptoKit
import Security

public enum AudibleAuth {

    // MARK: - UK Marketplace Constants

    public static let domain = "amazon.co.uk"
    public static let apiDomain = "api.audible.co.uk"
    public static let marketplaceId = "A2I9A3Q2GNFNGQ"
    public static let openidAssocHandle = "amzn_audible_ios_uk"
    public static let deviceType = "A2CZJZGLK2JJVM"

    // MARK: - Device Identity

    /// Generates an uppercase UUID hex string as the device serial.
    public static func generateDeviceSerial() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }

    /// Builds the client_id by hex-encoding "{serial}#A2CZJZGLK2JJVM" bytes.
    /// This matches the Audible iOS app's client_id format.
    public static func buildClientId(serial: String) -> String {
        let raw = "\(serial)#\(deviceType)"
        return raw.utf8.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - PKCE

    /// Generates a 32-byte random code verifier (base64url, no padding).
    public static func createCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// SHA256 hash of verifier, base64url-encoded (no padding).
    public static func createCodeChallenge(verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    // MARK: - OAuth URL

    /// Builds the Amazon OAuth sign-in URL with all required OpenID params.
    /// Uses manual percent-encoding to match Python's urlencode behavior —
    /// URLComponents leaves `:` and `/` unencoded in query values, but
    /// Amazon's OpenID parser requires them percent-encoded.
    public static func buildAuthURL(clientId: String, codeChallenge: String) -> URL {
        let params: [(String, String)] = [
            ("openid.oa2.response_type", "code"),
            ("openid.oa2.code_challenge_method", "S256"),
            ("openid.oa2.code_challenge", codeChallenge),
            ("openid.return_to", "https://www.amazon.co.uk/ap/maplanding"),
            ("openid.assoc_handle", openidAssocHandle),
            ("openid.identity", "http://specs.openid.net/auth/2.0/identifier_select"),
            ("pageId", "amzn_audible_ios"),
            ("accountStatusPolicy", "P1"),
            ("openid.claimed_id", "http://specs.openid.net/auth/2.0/identifier_select"),
            ("openid.mode", "checkid_setup"),
            ("openid.ns.oa2", "http://www.amazon.com/ap/ext/oauth/2"),
            ("openid.oa2.client_id", "device:\(clientId)"),
            ("openid.ns.pape", "http://specs.openid.net/extensions/pape/1.0"),
            ("marketPlaceId", marketplaceId),
            ("openid.oa2.scope", "device_auth_access"),
            ("forceMobileLayout", "true"),
            ("openid.ns", "http://specs.openid.net/auth/2.0"),
            ("openid.pape.max_auth_age", "0"),
        ]
        let query = params.map { key, value in
            let encodedKey = strictURLEncode(key)
            let encodedValue = strictURLEncode(value)
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return URL(string: "https://www.amazon.co.uk/ap/signin?\(query)")!
    }

    /// Percent-encodes a string for use in URL query parameters,
    /// matching Python's urllib.parse.quote behavior (encodes `:`, `/`, etc.)
    private static func strictURLEncode(_ string: String) -> String {
        // Only allow unreserved characters: A-Z a-z 0-9 - _ . ~
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Device Registration

    /// Builds the URLRequest for device registration (POST to /auth/register).
    public static func buildRegistrationRequest(
        authCode: String,
        codeVerifier: String,
        clientId: String,
        deviceSerial: String
    ) -> URLRequest {
        let url = URL(string: "https://api.amazon.co.uk/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Note: client_id here is the raw hex string (no "device:" prefix).
        // The "device:" prefix is only used in the OAuth URL, not in registration.
        let body: [String: Any] = [
            "requested_token_type": [
                "bearer",
                "mac_dms",
                "website_cookies",
                "store_authentication_cookie",
            ],
            "cookies": [
                "website_cookies": [] as [Any],
                "domain": ".amazon.co.uk",
            ] as [String: Any],
            "registration_data": [
                "domain": "Device",
                "app_version": "3.56.2",
                "device_serial": deviceSerial,
                "device_type": deviceType,
                "device_name": "%FIRST_NAME%%FIRST_NAME_POSSESSIVE_STRING%%DUPE_STRATEGY_1ST%Audible for iPhone",
                "os_version": "15.0.0",
                "software_version": "35602678",
                "device_model": "iPhone",
                "app_name": "Audible",
            ],
            "auth_data": [
                "client_id": clientId,
                "authorization_code": authCode,
                "code_verifier": codeVerifier,
                "code_algorithm": "SHA-256",
                "client_domain": "DeviceLegacy",
            ],
            "requested_extensions": ["device_info", "customer_info"],
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Request Signing

    public enum SigningError: Error {
        case invalidPEMKey
        case keyCreationFailed
        case signingFailed
    }

    /// Signs an API request with RSA SHA256 + adp_token.
    /// Adds x-adp-token, x-adp-alg, x-adp-signature headers.
    public static func signRequest(
        _ request: inout URLRequest,
        adpToken: String,
        privateKeyPEM: String
    ) throws {
        // 1. Parse PEM to SecKey
        let privateKey = try secKeyFromPEM(privateKeyPEM)

        // 2. Build signing string
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let timestamp = isoTimestamp()
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let signingString = "\(method)\n\(path)\n\(timestamp)\n\(body)\n\(adpToken)"

        // 3. Sign with RSA SHA256
        guard let signingData = signingString.data(using: .utf8) else {
            throw SigningError.signingFailed
        }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingData as CFData,
            &error
        ) as Data? else {
            throw SigningError.signingFailed
        }

        // 4. Set headers
        let base64Sig = signature.base64EncodedString()
        request.setValue("\(base64Sig):\(timestamp)", forHTTPHeaderField: "x-adp-signature")
        request.setValue("SHA256withRSA:1.0", forHTTPHeaderField: "x-adp-alg")
        request.setValue(adpToken, forHTTPHeaderField: "x-adp-token")
    }

    // MARK: - Token Refresh

    /// Builds a token refresh URLRequest.
    /// Uses the Audible-specific /auth/token endpoint (not OAuth /auth/o2/token).
    public static func buildTokenRefreshRequest(refreshToken: String) -> URLRequest {
        let url = URL(string: "https://api.amazon.co.uk/auth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "app_name", value: "Audible"),
            URLQueryItem(name: "app_version", value: "3.56.2"),
            URLQueryItem(name: "source_token", value: refreshToken),
            URLQueryItem(name: "requested_token_type", value: "access_token"),
            URLQueryItem(name: "source_token_type", value: "refresh_token"),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    // MARK: - Private Helpers

    /// Parses a PEM-encoded RSA private key into a SecKey.
    private static func secKeyFromPEM(_ pem: String) throws -> SecKey {
        // Strip PEM header/footer and whitespace
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let keyData = Data(base64Encoded: stripped) else {
            throw SigningError.invalidPEMKey
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw SigningError.keyCreationFailed
        }
        return secKey
    }

    /// Returns the current UTC timestamp in ISO 8601 format with nanosecond precision.
    private static func isoTimestamp() -> String {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // ISO8601DateFormatter doesn't support nanoseconds, so build manually
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: now)
        let year = comps.year!
        let month = comps.month!
        let day = comps.day!
        let hour = comps.hour!
        let minute = comps.minute!
        let second = comps.second!
        let nanosecond = comps.nanosecond!
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%09dZ",
            year, month, day, hour, minute, second, nanosecond
        )
    }
}

// MARK: - Data Extension for Base64URL

extension Data {
    /// Base64URL encoding without padding, as required by PKCE.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
