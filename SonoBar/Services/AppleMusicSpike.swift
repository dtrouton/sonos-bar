// SonoBar/Services/AppleMusicSpike.swift
// TEMPORARY — deleted after spike findings are documented (Task 0.6 of
// docs/superpowers/plans/2026-04-19-apple-music-integration.md).

#if DEBUG
import Foundation
import SonoBarKit

enum AppleMusicSpike {

    /// Writes the spike output to ~/Desktop/apple-music-spike.log so it's
    /// easy to recover without fishing through Console.app noise.
    private static let logURL: URL = {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent("apple-music-spike.log")
    }()

    private static func log(_ line: String) {
        print("[Spike] \(line)")
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    private static func resetLog() {
        try? FileManager.default.removeItem(at: logURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }

    /// Dumps everything relevant about the speaker's Apple Music browse + search surface.
    /// Run once per development setup, paste output into the findings doc, then delete.
    static func run(client: SOAPClient) async {
        resetLog()
        log("=============================================")
        log("=== APPLE MUSIC SMAPI SPIKE ================")
        log("=== Writing to \(logURL.path)")
        log("=============================================")

        // 1. Confirm the Apple Music service is linked.
        let account: MusicServiceDiscovery.ServiceAccount?
        do {
            account = try await MusicServiceDiscovery.findService(sid: 204, client: client)
        } catch {
            log("discoverService threw: \(error)")
            return
        }
        guard let account else {
            log("Apple Music NOT linked. Link it in the Sonos app first, then rerun.")
            if let all = try? await MusicServiceDiscovery.discoverServices(client: client) {
                log("Linked services on this Sonos:")
                for svc in all {
                    log("  - sid=\(svc.sid) name=\(svc.name) sn=\(svc.sn) type=\(svc.serviceType) auth=\(svc.authType)")
                }
            }
            return
        }
        log("Apple Music account: sid=\(account.sid) sn=\(account.sn) type=\(account.serviceType) auth=\(account.authType)")
        log("CDUDN: \(account.cdudn)")

        // Compact summary of Favorites — this is what "Favorites-as-library" would expose.
        log("")
        log("--- FAVORITES SUMMARY (FV:2, compact) ---")
        await dumpFavoritesSummary(client: client)

        // Full raw FV:2 dump for full inspection.
        log("")
        log("--- FV:2 raw (up to 50000 chars) ---")
        await dumpBrowseRaw(client: client, objectID: "FV:2", limit: 50000)

        // Also dump SQ: in full — user-saved queues, often include Apple Music tracks.
        log("")
        log("--- SQ: raw (up to 50000 chars) ---")
        await dumpBrowseRaw(client: client, objectID: "SQ:", limit: 50000)

        log("")
        log("=============================================")
        log("=== SPIKE COMPLETE — log at \(logURL.path)")
        log("=============================================")
    }

    private static func dumpBrowse(client: SOAPClient, objectID: String) async {
        do {
            let result = try await client.callAction(
                service: .contentDirectory,
                action: "Browse",
                params: [
                    ("ObjectID", objectID),
                    ("BrowseFlag", "BrowseDirectChildren"),
                    ("Filter", "*"),
                    ("StartingIndex", "0"),
                    ("RequestedCount", "20"),
                    ("SortCriteria", "")
                ]
            )
            let returned = result["NumberReturned"] ?? "?"
            let total = result["TotalMatches"] ?? "?"
            log("NumberReturned=\(returned) TotalMatches=\(total)")
            if let xml = result["Result"] {
                let snippet = String(xml.prefix(3000))
                log("Result XML (first 3000 chars):")
                log(snippet)
                if xml.count > 3000 {
                    log("...[truncated — total length \(xml.count)]")
                }
            }
        } catch {
            log("Browse error for \(objectID): \(error)")
        }
    }

    /// Compact summary: one line per favorite showing title, service hint, and item type.
    private static func dumpFavoritesSummary(client: SOAPClient) async {
        let xml: String
        do {
            let result = try await client.callAction(
                service: .contentDirectory,
                action: "Browse",
                params: [
                    ("ObjectID", "FV:2"),
                    ("BrowseFlag", "BrowseDirectChildren"),
                    ("Filter", "*"),
                    ("StartingIndex", "0"),
                    ("RequestedCount", "100"),
                    ("SortCriteria", "")
                ]
            )
            xml = result["Result"] ?? ""
        } catch {
            log("FV:2 summary error: \(error)")
            return
        }

        // Parse each <item>...</item> block with regex-light string scanning.
        let items = splitItems(xml)
        log("Found \(items.count) favorites:")
        for (i, item) in items.enumerated() {
            let title = extractTag(item, tag: "dc:title") ?? "(untitled)"
            let serviceHint = extractTag(item, tag: "r:description") ?? "(unknown)"
            let resURI = extractTag(item, tag: "res") ?? ""

            // Classify URI: album / playlist / track / radio / other
            let kind: String
            if resURI.contains("libraryplaylist") { kind = "Apple Music library playlist" }
            else if resURI.contains("playlist%3A") || resURI.contains("playlist:") { kind = "playlist" }
            else if resURI.contains("album%3A") || resURI.contains("album:") { kind = "album" }
            else if resURI.contains("song%3A") || resURI.contains("song:") { kind = "track" }
            else if resURI.hasPrefix("x-sonosapi-radio:") { kind = "radio station" }
            else if resURI.hasPrefix("x-sonosapi-stream:") { kind = "stream" }
            else if resURI.isEmpty { kind = "shortcut (no direct URI)" }
            else { kind = "other" }

            // Extract sid from URI if present
            var sidStr = ""
            if let sidRange = resURI.range(of: "sid=") {
                let tail = resURI[sidRange.upperBound...]
                let sid = tail.prefix(while: { $0.isNumber })
                if !sid.isEmpty { sidStr = " sid=\(sid)" }
            }

            log("  \(i + 1). \"\(title)\" — [\(serviceHint)] \(kind)\(sidStr)")
        }
    }

    private static func dumpBrowseRaw(client: SOAPClient, objectID: String, limit: Int) async {
        do {
            let result = try await client.callAction(
                service: .contentDirectory,
                action: "Browse",
                params: [
                    ("ObjectID", objectID),
                    ("BrowseFlag", "BrowseDirectChildren"),
                    ("Filter", "*"),
                    ("StartingIndex", "0"),
                    ("RequestedCount", "100"),
                    ("SortCriteria", "")
                ]
            )
            let returned = result["NumberReturned"] ?? "?"
            let total = result["TotalMatches"] ?? "?"
            log("NumberReturned=\(returned) TotalMatches=\(total)")
            if let xml = result["Result"] {
                let snippet = String(xml.prefix(limit))
                log(snippet)
                if xml.count > limit {
                    log("...[truncated at \(limit), total \(xml.count)]")
                }
            }
        } catch {
            log("Browse raw error \(objectID): \(error)")
        }
    }

    // MARK: - Tiny string scanners (spike-only, not production code)

    private static func splitItems(_ xml: String) -> [String] {
        var items: [String] = []
        var remaining = xml[...]
        while let start = remaining.range(of: "<item ") ?? remaining.range(of: "<container ") {
            let isContainer = remaining[start].contains("<container")
            let closeTag = isContainer ? "</container>" : "</item>"
            guard let end = remaining.range(of: closeTag, range: start.upperBound..<remaining.endIndex) else { break }
            items.append(String(remaining[start.lowerBound..<end.upperBound]))
            remaining = remaining[end.upperBound...]
        }
        return items
    }

    private static func extractTag(_ xml: String, tag: String) -> String? {
        // Match <tag ...>CONTENT</tag> or <tag>CONTENT</tag>, first occurrence only.
        guard let openStart = xml.range(of: "<\(tag)") else { return nil }
        let afterName = xml[openStart.upperBound...]
        guard let openEnd = afterName.firstIndex(of: ">") else { return nil }
        let contentStart = xml.index(after: openEnd)
        guard let closeRange = xml.range(of: "</\(tag)>", range: contentStart..<xml.endIndex) else { return nil }
        let raw = String(xml[contentStart..<closeRange.lowerBound])
        return raw.replacingOccurrences(of: "&amp;", with: "&")
                  .replacingOccurrences(of: "&lt;", with: "<")
                  .replacingOccurrences(of: "&gt;", with: ">")
                  .replacingOccurrences(of: "&quot;", with: "\"")
                  .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func dumpSearch(client: SOAPClient, searchId: String, term: String) async {
        do {
            let result = try await client.callAction(
                service: .musicServices,
                action: "Search",
                params: [
                    ("Id", searchId),
                    ("Term", term),
                    ("Index", "0"),
                    ("Count", "10"),
                ]
            )
            log("")
            log("Search [\(searchId) '\(term)']:")
            for (k, v) in result {
                let snippet = String(v.prefix(2000))
                log("  \(k) = \(snippet)\(v.count > 2000 ? "...[truncated]" : "")")
            }
        } catch {
            log("Search error [\(searchId) '\(term)']: \(error)")
        }
    }
}
#endif
