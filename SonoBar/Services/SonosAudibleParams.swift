// SonoBar/Services/SonosAudibleParams.swift

import Foundation
import SonoBarKit

/// Discovers and stores Audible Sonos service parameters from speaker room states.
struct SonosAudibleParams: Equatable {
    let sid: String          // "239"
    let sn: String           // "6"
    let desc: String         // "SA_RINCON61191_X_#Svc61191-0-Token"
    let marketplace: String  // "co.uk"

    /// Builds a Sonos play URI for an Audible book.
    func buildPlayURI(asin: String) -> String {
        "x-rincon-cpcontainer:00130000reftitle%3a\(asin)_\(marketplace)?sid=\(sid)&flags=0&sn=\(sn)"
    }

    /// Builds DIDL metadata for SetAVTransportURI.
    func buildPlayDIDL(asin: String, title: String, coverURL: String?) -> String {
        let escapedTitle = xmlEscape(title)
        let itemID = "00130000reftitle%3a\(asin)_\(marketplace)"
        var artTag = ""
        if let coverURL, !coverURL.isEmpty {
            artTag = "<upnp:albumArtURI>\(xmlEscape(coverURL))</upnp:albumArtURI>"
        }
        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="\(itemID)" parentID="-1" restricted="true">\
        <dc:title>\(escapedTitle)</dc:title>\
        <upnp:class>object.item.audioItem.audioBook</upnp:class>\
        <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">\(desc)</desc>\
        \(artTag)\
        </item></DIDL-Lite>
        """
    }

    // MARK: - Discovery

    /// Tries to discover Audible service params from room states.
    /// Looks for any media URI containing "sid=239".
    static func discover(from roomStates: [String: RoomSummary]) -> SonosAudibleParams? {
        for (_, summary) in roomStates {
            guard let mediaURI = summary.mediaURI, mediaURI.contains("sid=239") else { continue }

            // Parse sn from URI query string (e.g., "sn=6")
            guard let snValue = extractQueryParam("sn", from: mediaURI) else { continue }

            // Parse marketplace from URI item ID
            // URI example: x-rincon-cpcontainer:00130000reftitle%3aB08DC99YNB_co.uk?sid=239&flags=0&sn=6
            // Find the part between the last "_" before "?" and "?"
            guard let marketplace = extractMarketplace(from: mediaURI) else { continue }

            // Extract desc from mediaDIDL by finding <desc ...>...</desc>
            let descValue: String
            if let didl = summary.mediaDIDL, let parsed = extractDescFromDIDL(didl) {
                descValue = parsed
            } else {
                // Fallback to a sensible default if DIDL is missing
                continue
            }

            return SonosAudibleParams(
                sid: "239",
                sn: snValue,
                desc: descValue,
                marketplace: marketplace
            )
        }
        return nil
    }

    // MARK: - Persistence

    private static let sidKey = "audibleSonosSID"
    private static let snKey = "audibleSonosSN"
    private static let descKey = "audibleSonosDesc"
    private static let marketplaceKey = "audibleMarketplace"

    /// Loads from UserDefaults, or nil if not stored.
    static func load() -> SonosAudibleParams? {
        let defaults = UserDefaults.standard
        guard let sid = defaults.string(forKey: sidKey),
              let sn = defaults.string(forKey: snKey),
              let desc = defaults.string(forKey: descKey),
              let marketplace = defaults.string(forKey: marketplaceKey) else { return nil }
        return SonosAudibleParams(sid: sid, sn: sn, desc: desc, marketplace: marketplace)
    }

    /// Saves to UserDefaults.
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(sid, forKey: Self.sidKey)
        defaults.set(sn, forKey: Self.snKey)
        defaults.set(desc, forKey: Self.descKey)
        defaults.set(marketplace, forKey: Self.marketplaceKey)
    }

    /// Clears stored params.
    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: sidKey)
        defaults.removeObject(forKey: snKey)
        defaults.removeObject(forKey: descKey)
        defaults.removeObject(forKey: marketplaceKey)
    }

    // MARK: - Private Parsing Helpers

    /// Extracts a query parameter value from a URI string.
    private static func extractQueryParam(_ name: String, from uri: String) -> String? {
        guard let queryStart = uri.firstIndex(of: "?") else { return nil }
        let query = String(uri[uri.index(after: queryStart)...])
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == name {
                return String(parts[1])
            }
        }
        return nil
    }

    /// Extracts the marketplace suffix from a Sonos Audible URI.
    /// e.g. from "...reftitle%3aB08DC99YNB_co.uk?sid=239..." extracts "co.uk"
    private static func extractMarketplace(from uri: String) -> String? {
        // Get the path part before the query string
        let path: String
        if let qIdx = uri.firstIndex(of: "?") {
            path = String(uri[uri.startIndex..<qIdx])
        } else {
            path = uri
        }

        // Decode %3a to : for easier parsing
        let decoded = path.replacingOccurrences(of: "%3a", with: ":")
            .replacingOccurrences(of: "%3A", with: ":")

        // Find the last "_" which precedes the marketplace
        guard let lastUnderscore = decoded.lastIndex(of: "_") else { return nil }
        let marketplace = String(decoded[decoded.index(after: lastUnderscore)...])
        guard !marketplace.isEmpty else { return nil }
        return marketplace
    }

    /// Extracts the text content of the first <desc ...>...</desc> element from DIDL XML.
    private static func extractDescFromDIDL(_ didl: String) -> String? {
        // Find <desc followed by any attributes, then >content</desc>
        guard let descStart = didl.range(of: "<desc ") ?? didl.range(of: "<desc>") else { return nil }
        // Find the closing > of the opening tag
        let afterTag = didl[descStart.upperBound...]
        guard let closeAngle = afterTag.firstIndex(of: ">") else { return nil }
        let contentStart = didl.index(after: closeAngle)
        // Find </desc>
        guard let endTag = didl.range(of: "</desc>", range: contentStart..<didl.endIndex) else { return nil }
        return String(didl[contentStart..<endTag.lowerBound])
    }

    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
