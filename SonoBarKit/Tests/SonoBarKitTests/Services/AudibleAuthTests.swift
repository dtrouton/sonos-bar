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
        #expect(verifier.count == 43)
        #expect(!verifier.contains("+"))
        #expect(!verifier.contains("/"))
        #expect(!verifier.contains("="))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for scalar in verifier.unicodeScalars {
            #expect(allowed.contains(scalar), "Invalid character: \(scalar)")
        }
    }

    @Test func testCodeChallengeIsSHA256() {
        let verifier = "test_verifier_value"
        let challenge = AudibleAuth.createCodeChallenge(verifier: verifier)
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
        #expect(!challenge.contains("="))
        #expect(challenge.count == 43)
        let challenge2 = AudibleAuth.createCodeChallenge(verifier: verifier)
        #expect(challenge == challenge2)
        let challenge3 = AudibleAuth.createCodeChallenge(verifier: "different_verifier")
        #expect(challenge != challenge3)
    }

    // MARK: - Device Identity Tests

    @Test func testDeviceSerialIsUppercaseHex32() {
        let serial = AudibleAuth.generateDeviceSerial()
        #expect(serial.count == 32)
        let hexChars = CharacterSet(charactersIn: "0123456789ABCDEF")
        for scalar in serial.unicodeScalars {
            #expect(hexChars.contains(scalar), "Non-hex character: \(scalar)")
        }
        let serial2 = AudibleAuth.generateDeviceSerial()
        #expect(serial != serial2)
    }

    @Test func testBuildClientIdIsHexEncoded() {
        let serial = "D8BE1C18DA054A82"
        let clientId = AudibleAuth.buildClientId(serial: serial)
        // hex encoding of "D8BE1C18DA054A82#A2CZJZGLK2JJVM"
        let expected = "D8BE1C18DA054A82#A2CZJZGLK2JJVM".utf8.map { String(format: "%02x", $0) }.joined()
        #expect(clientId == expected)
    }

    // MARK: - OAuth URL Test

    @Test func testAuthURLContainsRequiredParams() {
        let hexClientId = AudibleAuth.buildClientId(serial: "TESTSERIAL123456")
        let challenge = "test_challenge_value"
        let url = AudibleAuth.buildAuthURL(clientId: hexClientId, codeChallenge: challenge)

        let urlString = url.absoluteString
        #expect(urlString.hasPrefix("https://www.amazon.co.uk/ap/signin?"))

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let params = Dictionary(
            uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") }
        )

        #expect(params["openid.oa2.response_type"] == "code")
        #expect(params["openid.oa2.code_challenge_method"] == "S256")
        #expect(params["openid.oa2.code_challenge"] == challenge)
        #expect(params["openid.oa2.client_id"] == "device:\(hexClientId)")
        #expect(params["openid.oa2.scope"] == "device_auth_access")
        #expect(params["openid.return_to"] == "https://www.amazon.co.uk/ap/maplanding")
        #expect(params["openid.assoc_handle"] == "amzn_audible_ios_uk")
        #expect(params["marketPlaceId"] == "A2I9A3Q2GNFNGQ")
        #expect(params["pageId"] == "amzn_audible_ios")
        #expect(params["openid.mode"] == "checkid_setup")
        #expect(params["openid.ns"] == "http://specs.openid.net/auth/2.0")
        #expect(params["openid.ns.oa2"] == "http://www.amazon.com/ap/ext/oauth/2")
        #expect(params["openid.ns.pape"] == "http://specs.openid.net/extensions/pape/1.0")
        #expect(params["openid.pape.max_auth_age"] == "0")
        #expect(params["forceMobileLayout"] == "true")
        #expect(params["accountStatusPolicy"] == "P1")
    }

    // MARK: - Device Registration Test

    @Test func testRegistrationRequestBody() throws {
        let hexClientId = AudibleAuth.buildClientId(serial: "SERIAL789")
        let request = AudibleAuth.buildRegistrationRequest(
            authCode: "AUTH_CODE_123",
            codeVerifier: "VERIFIER_456",
            clientId: hexClientId,
            deviceSerial: "SERIAL789"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.amazon.co.uk/auth/register")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        let authData = try #require(json["auth_data"] as? [String: Any])
        #expect(authData["authorization_code"] as? String == "AUTH_CODE_123")
        #expect(authData["code_verifier"] as? String == "VERIFIER_456")
        #expect(authData["client_id"] as? String == hexClientId)

        let regData = try #require(json["registration_data"] as? [String: Any])
        #expect(regData["device_serial"] as? String == "SERIAL789")
        #expect(regData["device_type"] as? String == "A2CZJZGLK2JJVM")
    }

    // MARK: - Request Signing Test

    @Test func testSignRequestAddsHeaders() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let keyData = try #require(SecKeyCopyExternalRepresentation(privateKey, &error) as Data?)
        let base64Key = keyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n\(base64Key)\n-----END RSA PRIVATE KEY-----"

        var request = URLRequest(url: URL(string: "https://api.audible.co.uk/1.0/library")!)
        request.httpMethod = "GET"

        let adpToken = "test-adp-token-value"
        try AudibleAuth.signRequest(&request, adpToken: adpToken, privateKeyPEM: pem)

        #expect(request.value(forHTTPHeaderField: "x-adp-token") == adpToken)
        #expect(request.value(forHTTPHeaderField: "x-adp-alg") == "SHA256withRSA:1.0")

        let sigHeader = try #require(request.value(forHTTPHeaderField: "x-adp-signature"))
        let parts = sigHeader.split(separator: ":", maxSplits: 1)
        #expect(parts.count == 2)
        #expect(Data(base64Encoded: String(parts[0])) != nil)
        #expect(String(parts[1]).hasSuffix("Z"))
    }

    // MARK: - Token Refresh Test

    @Test func testTokenRefreshRequestFormat() throws {
        let request = AudibleAuth.buildTokenRefreshRequest(
            refreshToken: "Atzr|REFRESH_TOKEN_123"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.amazon.co.uk/auth/token")

        let body = try #require(request.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let components = URLComponents(string: "http://x?\(bodyString)")!
        let params = Dictionary(
            uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") }
        )

        #expect(params["app_name"] == "Audible")
        #expect(params["source_token"] == "Atzr|REFRESH_TOKEN_123")
        #expect(params["requested_token_type"] == "access_token")
        #expect(params["source_token_type"] == "refresh_token")
    }
}
