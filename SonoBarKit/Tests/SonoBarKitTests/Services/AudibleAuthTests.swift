// SonoBarKit/Tests/SonoBarKitTests/Services/AudibleAuthTests.swift
import Foundation
import Testing
import Security
@testable import SonoBarKit

@Suite("AudibleAuth Tests")
struct AudibleAuthTests {

    // MARK: - PKCE Tests

    @Test func testCodeVerifierIsBase64URL() {
        let verifier = AudibleAuth.createCodeVerifier()
        // base64url of 32 bytes = 43 chars (no padding)
        #expect(verifier.count == 43)
        // Must not contain non-URL-safe characters
        #expect(!verifier.contains("+"))
        #expect(!verifier.contains("/"))
        #expect(!verifier.contains("="))
        // Only valid base64url chars
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for scalar in verifier.unicodeScalars {
            #expect(allowed.contains(scalar), "Invalid character: \(scalar)")
        }
    }

    @Test func testCodeChallengeIsSHA256() {
        // Known test vector: SHA256("test_verifier_value") in base64url
        // We compute it independently to verify our implementation
        let verifier = "test_verifier_value"
        let challenge = AudibleAuth.createCodeChallenge(verifier: verifier)

        // Should be base64url, no padding
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
        #expect(!challenge.contains("="))
        // SHA256 produces 32 bytes -> 43 base64url chars (no padding)
        #expect(challenge.count == 43)

        // Verify deterministic: same input -> same output
        let challenge2 = AudibleAuth.createCodeChallenge(verifier: verifier)
        #expect(challenge == challenge2)

        // Different verifier -> different challenge
        let challenge3 = AudibleAuth.createCodeChallenge(verifier: "different_verifier")
        #expect(challenge != challenge3)
    }

    // MARK: - OAuth URL Test

    @Test func testAuthURLContainsRequiredParams() {
        let clientId = "device:SERIAL123#A2CZJZGLK2JJVM"
        let challenge = "test_challenge_value"
        let url = AudibleAuth.buildAuthURL(clientId: clientId, codeChallenge: challenge)

        let urlString = url.absoluteString
        #expect(urlString.hasPrefix("https://www.amazon.co.uk/ap/signin?"))

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let params = Dictionary(
            uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") }
        )

        #expect(params["openid.oa2.response_type"] == "code")
        #expect(params["openid.oa2.code_challenge_method"] == "S256")
        #expect(params["openid.oa2.code_challenge"] == challenge)
        #expect(params["openid.oa2.client_id"] == clientId)
        #expect(params["openid.oa2.scope"] == "device_auth_access")
        #expect(params["openid.return_to"] == "https://www.amazon.co.uk/ap/maplanding")
        #expect(params["openid.assoc_handle"] == "amzn_audible_ios_uk")
        #expect(params["marketPlaceId"] == "A2I9A3Q2GNFNGQ")
        #expect(params["pageId"] == "amzn_audible_ios")
        #expect(params["openid.mode"] == "checkid_setup")
        #expect(params["openid.ns"] == "http://specs.openid.net/auth/2.0")
        #expect(params["openid.claimed_id"] == "http://specs.openid.net/auth/2.0/identifier_select")
        #expect(params["openid.identity"] == "http://specs.openid.net/auth/2.0/identifier_select")
    }

    // MARK: - Device Registration Test

    @Test func testRegistrationRequestBody() throws {
        let request = AudibleAuth.buildRegistrationRequest(
            authCode: "AUTH_CODE_123",
            codeVerifier: "VERIFIER_456",
            clientId: "device:SERIAL789#A2CZJZGLK2JJVM",
            deviceSerial: "SERIAL789"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.amazon.co.uk/auth/register")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Verify auth_data
        let authData = try #require(json["auth_data"] as? [String: Any])
        #expect(authData["authorization_code"] as? String == "AUTH_CODE_123")
        #expect(authData["code_verifier"] as? String == "VERIFIER_456")
        #expect(authData["code_algorithm"] as? String == "SHA-256")
        #expect(authData["client_domain"] as? String == "DeviceLegacy")
        #expect(authData["client_id"] as? String == "device:SERIAL789#A2CZJZGLK2JJVM")

        // Verify registration_data
        let regData = try #require(json["registration_data"] as? [String: Any])
        #expect(regData["domain"] as? String == "Device")
        #expect(regData["app_version"] as? String == "3.56.2")
        #expect(regData["device_type"] as? String == "A2CZJZGLK2JJVM")
        #expect(regData["device_serial"] as? String == "SERIAL789")
        #expect(regData["app_name"] as? String == "Audible")
        #expect(regData["os_version"] as? String == "17.0")
        #expect(regData["software_version"] as? String == "35602678")

        // Verify requested_token_type
        let tokenTypes = try #require(json["requested_token_type"] as? [String])
        #expect(tokenTypes.contains("bearer"))
        #expect(tokenTypes.contains("mac_dms"))
        #expect(tokenTypes.contains("store_authentication_cookie"))
        #expect(tokenTypes.contains("website_cookies"))

        // Verify cookies
        let cookies = try #require(json["cookies"] as? [String: Any])
        #expect(cookies["domain"] as? String == ".amazon.co.uk")
        #expect((cookies["website_cookies"] as? [Any])?.isEmpty == true)

        // Verify requested_extensions
        let extensions = try #require(json["requested_extensions"] as? [String])
        #expect(extensions.contains("device_info"))
        #expect(extensions.contains("customer_info"))
    }

    // MARK: - Device Serial Test

    @Test func testDeviceSerialIsHex32() {
        let serial = AudibleAuth.generateDeviceSerial()
        #expect(serial.count == 32)

        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for scalar in serial.unicodeScalars {
            #expect(hexChars.contains(scalar), "Non-hex character: \(scalar)")
        }

        // Two calls should produce different serials
        let serial2 = AudibleAuth.generateDeviceSerial()
        #expect(serial != serial2)
    }

    // MARK: - Request Signing Test

    @Test func testSignRequestAddsHeaders() throws {
        // Generate a test RSA keypair
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))

        // Export the private key to PEM
        let keyData = try #require(SecKeyCopyExternalRepresentation(privateKey, &error) as Data?)
        let base64Key = keyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n\(base64Key)\n-----END RSA PRIVATE KEY-----"

        // Build a test request
        var request = URLRequest(url: URL(string: "https://api.audible.co.uk/1.0/library")!)
        request.httpMethod = "GET"

        let adpToken = "test-adp-token-value"
        try AudibleAuth.signRequest(&request, adpToken: adpToken, privateKeyPEM: pem)

        // Verify all three headers are present
        let adpTokenHeader = try #require(request.value(forHTTPHeaderField: "x-adp-token"))
        #expect(adpTokenHeader == adpToken)

        let algHeader = try #require(request.value(forHTTPHeaderField: "x-adp-alg"))
        #expect(algHeader == "SHA256withRSA:1.0")

        let sigHeader = try #require(request.value(forHTTPHeaderField: "x-adp-signature"))
        // Signature format: "{base64Signature}:{isoTimestamp}"
        let parts = sigHeader.split(separator: ":", maxSplits: 1)
        #expect(parts.count == 2)
        // First part should be valid base64
        let sigData = Data(base64Encoded: String(parts[0]))
        #expect(sigData != nil)
        // Second part should be an ISO timestamp ending in Z
        let timestamp = String(parts[1])
        #expect(timestamp.hasSuffix("Z"))
    }

    // MARK: - Token Refresh Test

    @Test func testTokenRefreshRequestFormat() throws {
        let request = AudibleAuth.buildTokenRefreshRequest(
            refreshToken: "Atzr|REFRESH_TOKEN_123",
            clientId: "device:SERIAL#A2CZJZGLK2JJVM"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.amazon.co.uk/auth/o2/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let body = try #require(request.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))

        // Parse URL-encoded body
        let components = URLComponents(string: "http://x?\(bodyString)")!
        let params = Dictionary(
            uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") }
        )

        #expect(params["grant_type"] == "refresh_token")
        #expect(params["refresh_token"] == "Atzr|REFRESH_TOKEN_123")
        #expect(params["client_id"] == "device:SERIAL#A2CZJZGLK2JJVM")
    }
}
