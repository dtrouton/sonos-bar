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
    /// clientId format: "device:{deviceSerial}#A2CZJZGLK2JJVM"
    public static func buildAuthURL(clientId: String, codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://www.amazon.co.uk/ap/signin")!
        components.queryItems = [
            // OpenID 2.0 base
            URLQueryItem(name: "openid.ns", value: "http://specs.openid.net/auth/2.0"),
            URLQueryItem(name: "openid.mode", value: "checkid_setup"),
            URLQueryItem(name: "openid.claimed_id", value: "http://specs.openid.net/auth/2.0/identifier_select"),
            URLQueryItem(name: "openid.identity", value: "http://specs.openid.net/auth/2.0/identifier_select"),
            URLQueryItem(name: "openid.return_to", value: "https://www.amazon.co.uk/ap/maplanding"),
            URLQueryItem(name: "openid.assoc_handle", value: openidAssocHandle),
            // OAuth 2.0 extension — MUST declare namespace for Amazon to include auth code
            URLQueryItem(name: "openid.ns.oa2", value: "http://www.amazon.com/ap/ext/oauth/2"),
            URLQueryItem(name: "openid.oa2.response_type", value: "code"),
            URLQueryItem(name: "openid.oa2.code_challenge_method", value: "S256"),
            URLQueryItem(name: "openid.oa2.code_challenge", value: codeChallenge),
            URLQueryItem(name: "openid.oa2.client_id", value: clientId),
            URLQueryItem(name: "openid.oa2.scope", value: "device_auth_access"),
            // Amazon/Audible specific
            URLQueryItem(name: "marketPlaceId", value: marketplaceId),
            URLQueryItem(name: "pageId", value: "amzn_audible_ios"),
            URLQueryItem(name: "accountStatusPolicy", value: "P1"),
        ]
        return components.url!
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

        let body: [String: Any] = [
            "auth_data": [
                "authorization_code": authCode,
                "code_verifier": codeVerifier,
                "code_algorithm": "SHA-256",
                "client_domain": "DeviceLegacy",
                "client_id": clientId,
            ],
            "registration_data": [
                "domain": "Device",
                "app_version": "3.56.2",
                "device_type": deviceType,
                "device_serial": deviceSerial,
                "app_name": "Audible",
                "os_version": "17.0",
                "software_version": "35602678",
            ],
            "requested_token_type": ["bearer", "mac_dms", "store_authentication_cookie", "website_cookies"],
            "cookies": [
                "domain": ".amazon.co.uk",
                "website_cookies": [] as [Any],
            ] as [String: Any],
            "requested_extensions": ["device_info", "customer_info"],
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Device Serial

    /// Generates a random hex device serial (32 chars).
    public static func generateDeviceSerial() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
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
    public static func buildTokenRefreshRequest(
        refreshToken: String,
        clientId: String
    ) -> URLRequest {
        let url = URL(string: "https://api.amazon.co.uk/auth/o2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
        ]
        // percentEncodedQuery gives us the properly encoded body
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
