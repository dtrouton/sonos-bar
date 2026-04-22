// AppleMusicCredentialsExtractor.swift
// SonoBarKit
//
// Extracts playback credentials (sn + accountToken) from a Sonos favorite's DIDL.
// Apple Music favorites embed the cdudn token inside <r:resMD>, HTML-entity-encoded.
// See docs/superpowers/notes/2026-04-19-apple-music-smapi-spike.md for the fixture
// shape this parser is designed against.

import Foundation

public enum AppleMusicCredentialsExtractor {

    /// Parses favorites DIDL (as returned by ContentDirectory.Browse on FV:2) and returns
    /// credentials from the first Apple Music entry found. Returns nil if no sid=204
    /// entry with recoverable, well-formed credentials exists.
    public static func extract(favoritesDIDL: String) -> AppleMusicCredentials? {
        let items = splitItems(favoritesDIDL)
        for item in items {
            guard let rawRes = extractTag(item, tag: "res"), rawRes.contains("sid=204") else { continue }
            // The res URI has its ampersands entity-encoded as "&amp;" in DIDL.
            let res = htmlDecode(rawRes)
            guard let sn = extractQueryParam("sn", from: res),
                  let snInt = Int(sn) else { continue }

            // The account token lives inside <r:resMD>, which contains entity-encoded DIDL.
            guard let resMD = extractTag(item, tag: "r:resMD") else { continue }
            let decoded = htmlDecode(resMD)
            guard let descValue = extractTag(decoded, tag: "desc"),
                  let token = parseAccountToken(from: descValue),
                  isHex(token) else { continue }

            return AppleMusicCredentials(sn: snInt, accountToken: token)
        }
        return nil
    }

    // MARK: - Parsing helpers

    /// Extracts the account token from a desc like
    /// "SA_RINCON52231_X_#Svc52231-890cb54f-Token" → "890cb54f".
    private static func parseAccountToken(from desc: String) -> String? {
        guard let svcRange = desc.range(of: "#Svc") ?? desc.range(of: "_Svc") else { return nil }
        let afterSvc = desc[svcRange.upperBound...]
        let afterDigits = afterSvc.drop(while: { $0.isNumber })
        guard afterDigits.first == "-" else { return nil }
        let tokenAndRest = afterDigits.dropFirst()
        guard let tokenEnd = tokenAndRest.range(of: "-Token") else { return nil }
        let token = String(tokenAndRest[..<tokenEnd.lowerBound])
        return token.isEmpty ? nil : token
    }

    /// Returns true only if the string is non-empty and contains only 0-9 / a-f / A-F.
    /// Real Apple Music account tokens are lowercase hex — this guards against malformed
    /// or hostile DIDL injecting unsafe characters that would later flow into a DIDL string.
    private static func isHex(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return s.allSatisfy { $0.isHexDigit }
    }

    /// Extracts a query parameter value from a URI.
    private static func extractQueryParam(_ name: String, from uri: String) -> String? {
        guard let q = uri.firstIndex(of: "?") else { return nil }
        let query = uri[uri.index(after: q)...]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == name { return String(kv[1]) }
        }
        return nil
    }

    /// Splits a DIDL document into individual <item>...</item> and <container>...</container> blocks.
    private static func splitItems(_ xml: String) -> [String] {
        var items: [String] = []
        var remaining = xml[...]
        while let start = remaining.range(of: "<item ") ?? remaining.range(of: "<container ") {
            let isContainer = remaining[start.lowerBound...].hasPrefix("<container")
            let closeTag = isContainer ? "</container>" : "</item>"
            guard let end = remaining.range(of: closeTag, range: start.upperBound..<remaining.endIndex)
            else { break }
            items.append(String(remaining[start.lowerBound..<end.upperBound]))
            remaining = remaining[end.upperBound...]
        }
        return items
    }

    /// Extracts the text content of the first <tag ...>CONTENT</tag> element.
    private static func extractTag(_ xml: String, tag: String) -> String? {
        guard let openStart = xml.range(of: "<\(tag)") else { return nil }
        let afterName = xml[openStart.upperBound...]
        guard let openEnd = afterName.firstIndex(of: ">") else { return nil }
        let contentStart = xml.index(after: openEnd)
        guard let closeRange = xml.range(of: "</\(tag)>", range: contentStart..<xml.endIndex)
        else { return nil }
        return String(xml[contentStart..<closeRange.lowerBound])
    }

    /// Decodes the five standard XML entities (sufficient for Sonos's <r:resMD> payload).
    private static func htmlDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&apos;", with: "'")
    }
}
