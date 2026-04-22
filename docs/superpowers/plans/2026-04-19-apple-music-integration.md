# Apple Music Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Apple Music catalog search + queue-append playback to SonoBar using the public iTunes Search API and credentials extracted from existing speaker favorites. No MusicKit, no $99/yr.

**Architecture:** Three new components in `SonoBarKit` (models, iTunes client, credential extractor + URI helpers), one new search view + album detail view in `SonoBar`, plus AppState integration. Library browsing is explicitly out of scope (unreachable without MusicKit).

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Package Manager, Swift Testing (`import Testing`). Existing plumbing: `SOAPClient`, `HTTPClientProtocol`, `ContentBrowser`, `PlaybackController`, `DIDLParser`.

**Design reference:** [`docs/superpowers/specs/2026-04-19-apple-music-integration-design.md`](../specs/2026-04-19-apple-music-integration-design.md)

**Spike findings (REQUIRED reading before starting):** [`docs/superpowers/notes/2026-04-19-apple-music-smapi-spike.md`](../notes/2026-04-19-apple-music-smapi-spike.md) — documents why this design deviates from the usual SMAPI approach. The playback constants (sn, account token format, URI templates) used in Tasks 2 and 3 are taken from the spike's verified live-speaker test.

---

## Task 1: Models (`AppleMusicModels.swift`)

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Models/AppleMusicModels.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Models/AppleMusicModelsTests.swift`

- [ ] **Step 1: Write failing tests**

Create `SonoBarKit/Tests/SonoBarKitTests/Models/AppleMusicModelsTests.swift`:

```swift
import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicModels Tests")
struct AppleMusicModelsTests {

    @Test("Track has expected properties")
    func trackShape() {
        let t = AppleMusicTrack(
            id: "1422700837",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "Greatest Hits",
            albumId: "1422700834",
            artworkURL: URL(string: "https://example.com/600x600bb.jpg"),
            durationSec: 355
        )
        #expect(t.id == "1422700837")
        #expect(t.albumId == "1422700834")
    }

    @Test("Album has expected properties")
    func albumShape() {
        let a = AppleMusicAlbum(
            id: "1649042949",
            title: "Dreaming of Bones",
            artist: "Someone",
            artworkURL: nil,
            trackCount: 9
        )
        #expect(a.trackCount == 9)
    }

    @Test("Artist has expected properties")
    func artistShape() {
        let a = AppleMusicArtist(id: "909253", name: "Jack Johnson")
        #expect(a.name == "Jack Johnson")
    }

    @Test("Credentials equality works")
    func credentialsEquality() {
        let a = AppleMusicCredentials(sn: 19, accountToken: "890cb54f")
        let b = AppleMusicCredentials(sn: 19, accountToken: "890cb54f")
        let c = AppleMusicCredentials(sn: 20, accountToken: "890cb54f")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Error equality")
    func errorEquality() {
        #expect(AppleMusicError.notLinked == AppleMusicError.notLinked)
        #expect(AppleMusicError.httpError(500) != AppleMusicError.httpError(404))
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicModelsTests
```
Expected: compilation error — types undefined.

- [ ] **Step 3: Implement models**

Create `SonoBarKit/Sources/SonoBarKit/Models/AppleMusicModels.swift`:

```swift
// AppleMusicModels.swift
// SonoBarKit
//
// Value types for Apple Music content surfaced via the iTunes Search API
// and credentials extracted from Sonos favorites.

import Foundation

public struct AppleMusicTrack: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let artist: String?
    public let album: String?
    public let albumId: String?
    public let artworkURL: URL?
    public let durationSec: Int?

    public init(id: String, title: String, artist: String?, album: String?,
                albumId: String?, artworkURL: URL?, durationSec: Int?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.artworkURL = artworkURL
        self.durationSec = durationSec
    }
}

public struct AppleMusicAlbum: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let artist: String?
    public let artworkURL: URL?
    public let trackCount: Int?

    public init(id: String, title: String, artist: String?, artworkURL: URL?, trackCount: Int?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.trackCount = trackCount
    }
}

public struct AppleMusicArtist: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AppleMusicSearchResults: Sendable, Equatable {
    public let tracks: [AppleMusicTrack]
    public let albums: [AppleMusicAlbum]
    public let artists: [AppleMusicArtist]

    public init(tracks: [AppleMusicTrack], albums: [AppleMusicAlbum], artists: [AppleMusicArtist]) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
    }
}

public enum AppleMusicPlayable: Sendable, Equatable {
    case track(AppleMusicTrack)
    case album(AppleMusicAlbum)

    public var id: String {
        switch self {
        case .track(let t): return t.id
        case .album(let a): return a.id
        }
    }

    public var title: String {
        switch self {
        case .track(let t): return t.title
        case .album(let a): return a.title
        }
    }

    public var artworkURL: URL? {
        switch self {
        case .track(let t): return t.artworkURL
        case .album(let a): return a.artworkURL
        }
    }
}

/// Playback credentials extracted from a Sonos favorite. The sn and accountToken values
/// come from the speaker's live state — we do NOT construct them, because the
/// ListAvailableServices sn and the node-sonos-http-api "-0-" token are both wrong for
/// modern Apple Music linkages (see spike findings).
public struct AppleMusicCredentials: Sendable, Equatable {
    public let sn: Int
    public let accountToken: String

    public init(sn: Int, accountToken: String) {
        self.sn = sn
        self.accountToken = accountToken
    }
}

public enum AppleMusicError: Error, Sendable, Equatable {
    case notLinked
    case networkError
    case httpError(Int)
    case invalidResponse
}
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicModelsTests
```
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Models/AppleMusicModels.swift \
        SonoBarKit/Tests/SonoBarKitTests/Models/AppleMusicModelsTests.swift
git commit -m "feat(apple-music): add model types and credentials struct"
```

---

## Task 2: URI + DIDL Helpers (`AppleMusicURIs.swift`)

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/AppleMusicURIs.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicURIsTests.swift`

- [ ] **Step 1: Write failing tests**

Create `SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicURIsTests.swift`:

```swift
import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicURIs Tests")
struct AppleMusicURIsTests {

    private let creds = AppleMusicCredentials(sn: 19, accountToken: "890cb54f")

    @Test("Track URI matches verified spike format")
    func trackURI() {
        // This is the exact URI format that succeeded in the Task 0 spike's
        // AddURIToQueue live-speaker test.
        let uri = AppleMusicURIs.trackURI(id: "1422700837", sn: 19)
        #expect(uri == "x-sonos-http:song%3a1422700837.mp4?sid=204&flags=8224&sn=19")
    }

    @Test("Album container URI uses cpcontainer prefix, no query string")
    func albumURI() {
        // Verified in spike: album container URIs take no sid/sn/flags suffix.
        #expect(AppleMusicURIs.albumContainerURI(id: "1649042949") ==
                "x-rincon-cpcontainer:1004206calbum%3a1649042949")
    }

    @Test("DIDL for track uses extracted account token, not hardcoded 0")
    func didlTrack() {
        let track = AppleMusicTrack(id: "1422700837", title: "Bohemian Rhapsody",
                                    artist: "Queen", album: "Greatest Hits",
                                    albumId: "1422700834",
                                    artworkURL: URL(string: "https://example.com/art.jpg"),
                                    durationSec: 355)
        let didl = AppleMusicURIs.didl(for: .track(track), credentials: creds)
        #expect(didl.contains("object.item.audioItem.musicTrack"))
        #expect(didl.contains("SA_RINCON52231_X_#Svc52231-890cb54f-Token"))
        #expect(!didl.contains("-0-Token"))
        #expect(didl.contains("<dc:title>Bohemian Rhapsody</dc:title>"))
    }

    @Test("DIDL escapes special XML characters in title")
    func didlEscapesTitle() {
        let track = AppleMusicTrack(id: "1", title: "Rock & Roll",
                                    artist: nil, album: nil, albumId: nil,
                                    artworkURL: nil, durationSec: nil)
        let didl = AppleMusicURIs.didl(for: .track(track), credentials: creds)
        #expect(didl.contains("Rock &amp; Roll"))
        #expect(!didl.contains("Rock & Roll</dc:title>"))
    }

    @Test("DIDL for album uses container class")
    func didlAlbum() {
        let album = AppleMusicAlbum(id: "1649042949", title: "Dreaming of Bones",
                                    artist: nil, artworkURL: nil, trackCount: 9)
        let didl = AppleMusicURIs.didl(for: .album(album), credentials: creds)
        #expect(didl.contains("object.container.album.musicAlbum"))
        #expect(didl.contains("890cb54f"))
    }

    @Test("Different credentials produce different DIDL tokens")
    func differentCreds() {
        let track = AppleMusicTrack(id: "1", title: "X", artist: nil, album: nil,
                                    albumId: nil, artworkURL: nil, durationSec: nil)
        let a = AppleMusicURIs.didl(for: .track(track),
                                    credentials: AppleMusicCredentials(sn: 19, accountToken: "aaaaaaaa"))
        let b = AppleMusicURIs.didl(for: .track(track),
                                    credentials: AppleMusicCredentials(sn: 19, accountToken: "bbbbbbbb"))
        #expect(a.contains("aaaaaaaa"))
        #expect(b.contains("bbbbbbbb"))
        #expect(a != b)
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicURIsTests
```

- [ ] **Step 3: Implement**

Create `SonoBarKit/Sources/SonoBarKit/Services/AppleMusicURIs.swift`:

```swift
// AppleMusicURIs.swift
// SonoBarKit
//
// Pure URI and DIDL metadata construction for Apple Music playback on Sonos.
// URI templates and account-token format verified against a live speaker in the
// Task 0 spike; see docs/superpowers/notes/2026-04-19-apple-music-smapi-spike.md.

import Foundation

public enum AppleMusicURIs {

    public static let serviceID = 204
    public static let serviceType = 52231   // serviceID * 256 + 7

    public static func trackURI(id: String, sn: Int) -> String {
        "x-sonos-http:song%3a\(id).mp4?sid=\(serviceID)&flags=8224&sn=\(sn)"
    }

    public static func albumContainerURI(id: String) -> String {
        "x-rincon-cpcontainer:1004206calbum%3a\(id)"
    }

    public static func didl(for item: AppleMusicPlayable,
                            credentials: AppleMusicCredentials) -> String {
        let title = xmlEscape(item.title)
        let upnpClass = upnpClass(for: item)
        let itemID = itemID(for: item)
        let parentID = parentID(for: item)
        let artTag = item.artworkURL.map {
            "<upnp:albumArtURI>\(xmlEscape($0.absoluteString))</upnp:albumArtURI>"
        } ?? ""
        let desc = "SA_RINCON\(serviceType)_X_#Svc\(serviceType)-\(credentials.accountToken)-Token"

        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="\(itemID)" parentID="\(parentID)" restricted="true">\
        <dc:title>\(title)</dc:title>\
        <upnp:class>\(upnpClass)</upnp:class>\
        <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">\(desc)</desc>\
        \(artTag)\
        </item></DIDL-Lite>
        """
    }

    private static func upnpClass(for item: AppleMusicPlayable) -> String {
        switch item {
        case .track: return "object.item.audioItem.musicTrack"
        case .album: return "object.container.album.musicAlbum"
        }
    }

    private static func itemID(for item: AppleMusicPlayable) -> String {
        switch item {
        case .track(let t): return "10032028song%3a\(t.id)"
        case .album(let a): return "1004206calbum%3a\(a.id)"
        }
    }

    private static func parentID(for item: AppleMusicPlayable) -> String {
        switch item {
        case .track: return "00020000song:"
        case .album: return "00020000album:"
        }
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicURIsTests
```
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/AppleMusicURIs.swift \
        SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicURIsTests.swift
git commit -m "feat(apple-music): add URI/DIDL helpers parameterized by extracted credentials"
```

---

## Task 3: Credential extractor (`AppleMusicCredentialsExtractor`)

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/AppleMusicCredentialsExtractor.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicCredentialsExtractorTests.swift`

- [ ] **Step 1: Write failing tests with fixtures from real spike output**

Create `SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicCredentialsExtractorTests.swift`:

```swift
import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicCredentialsExtractor Tests")
struct AppleMusicCredentialsExtractorTests {

    /// Real DIDL snippet captured from the Task 0 spike — one Apple Music favorite.
    private static let favoriteDIDL = """
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
<item id="FV:2/44" parentID="FV:2" restricted="false">\
<dc:title>Dreaming of Bones</dc:title>\
<upnp:class>object.itemobject.item.sonos-favorite</upnp:class>\
<r:ordinal>2</r:ordinal>\
<res protocolInfo="x-rincon-cpcontainer:*:*:*">x-rincon-cpcontainer:1004206calbum%3A1649042949?sid=204&amp;flags=8300&amp;sn=19</res>\
<r:type>instantPlay</r:type>\
<r:description>Apple Music</r:description>\
<r:resMD>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;1004206calbum%3A1649042949&quot; parentID=&quot;1004206calbum%3A1649042949&quot; restricted=&quot;true&quot;&gt;&lt;dc:title&gt;Dreaming of Bones&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id=&quot;cdudn&quot; nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;SA_RINCON52231_X_#Svc52231-890cb54f-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</r:resMD>\
</item>\
</DIDL-Lite>
"""

    /// Favorites with only non-Apple-Music entries.
    private static let nonAppleMusicFavoriteDIDL = """
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
<item id="FV:2/41" parentID="FV:2" restricted="false">\
<dc:title>Discover Sonos Radio</dc:title>\
<res></res>\
<r:description>Sonos Radio</r:description>\
</item>\
</DIDL-Lite>
"""

    @Test("Extracts sn=19 and token from real favorite DIDL")
    func extractsFromAppleMusicFavorite() {
        let creds = AppleMusicCredentialsExtractor.extract(favoritesDIDL: Self.favoriteDIDL)
        #expect(creds?.sn == 19)
        #expect(creds?.accountToken == "890cb54f")
    }

    @Test("Returns nil when no Apple Music favorites present")
    func nilOnNoAppleMusic() {
        let creds = AppleMusicCredentialsExtractor.extract(favoritesDIDL: Self.nonAppleMusicFavoriteDIDL)
        #expect(creds == nil)
    }

    @Test("Returns nil on empty DIDL")
    func nilOnEmpty() {
        #expect(AppleMusicCredentialsExtractor.extract(favoritesDIDL: "<DIDL-Lite></DIDL-Lite>") == nil)
    }

    @Test("Returns nil on malformed DIDL")
    func nilOnMalformed() {
        #expect(AppleMusicCredentialsExtractor.extract(favoritesDIDL: "not xml") == nil)
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicCredentialsExtractorTests
```

- [ ] **Step 3: Implement**

Create `SonoBarKit/Sources/SonoBarKit/Services/AppleMusicCredentialsExtractor.swift`:

```swift
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
    /// entry with recoverable credentials exists.
    public static func extract(favoritesDIDL: String) -> AppleMusicCredentials? {
        let items = splitItems(favoritesDIDL)
        for item in items {
            guard let res = extractTag(item, tag: "res"), res.contains("sid=204"),
                  let sn = extractQueryParam("sn", from: res),
                  let snInt = Int(sn) else { continue }

            // The account token lives inside <r:resMD>, which contains entity-encoded DIDL.
            guard let resMD = extractTag(item, tag: "r:resMD") else { continue }
            let decoded = htmlDecode(resMD)
            guard let descValue = extractTag(decoded, tag: "desc"),
                  let token = parseAccountToken(from: descValue) else { continue }

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
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicCredentialsExtractorTests
```
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/AppleMusicCredentialsExtractor.swift \
        SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicCredentialsExtractorTests.swift
git commit -m "feat(apple-music): extract sn and account token from favorites DIDL"
```

---

## Task 4: `ITunesSearchClient` — search + lookup

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/ITunesSearchClient.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Services/ITunesSearchClientTests.swift`

- [ ] **Step 1: Write failing tests**

Create `SonoBarKit/Tests/SonoBarKitTests/Services/ITunesSearchClientTests.swift`:

```swift
import Testing
import Foundation
@testable import SonoBarKit

@Suite("ITunesSearchClient Tests")
struct ITunesSearchClientTests {

    /// iTunes returns separate responses per entity; stub per-entity responses.
    final class SwitchingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
        var responses: [String: Data] = [:]
        var statusCode: Int = 200

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let entity = comps.queryItems?.first(where: { $0.name == "entity" })?.value ?? ""
            let body = responses[entity] ?? Data("{\"resultCount\":0,\"results\":[]}".utf8)
            let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            return (body, response)
        }
    }

    private static let songJSON = """
    {"resultCount":1,"results":[{
      "wrapperType":"track","kind":"song",
      "trackId":1422700837,
      "artistId":3296287,
      "collectionId":1422700834,
      "artistName":"Queen","collectionName":"Greatest Hits","trackName":"Bohemian Rhapsody",
      "artworkUrl100":"https://example.com/100x100bb.jpg",
      "trackTimeMillis":354947
    }]}
    """.data(using: .utf8)!

    private static let albumJSON = """
    {"resultCount":1,"results":[{
      "wrapperType":"collection","collectionType":"Album",
      "collectionId":1422700834,"artistId":3296287,
      "collectionName":"Greatest Hits","artistName":"Queen",
      "artworkUrl100":"https://example.com/100x100bb.jpg",
      "trackCount":17
    }]}
    """.data(using: .utf8)!

    private static let artistJSON = """
    {"resultCount":1,"results":[{
      "wrapperType":"artist","artistType":"Artist",
      "artistId":3296287,"artistName":"Queen"
    }]}
    """.data(using: .utf8)!

    @Test("Search merges tracks, albums, and artists")
    func search() async throws {
        let mock = SwitchingHTTPClient()
        mock.responses["song"] = Self.songJSON
        mock.responses["album"] = Self.albumJSON
        mock.responses["musicArtist"] = Self.artistJSON
        let client = ITunesSearchClient(country: "GB", httpClient: mock)

        let r = try await client.search("queen")
        #expect(r.tracks.count == 1)
        #expect(r.tracks[0].id == "1422700837")
        #expect(r.tracks[0].title == "Bohemian Rhapsody")
        #expect(r.tracks[0].durationSec == 354)
        #expect(r.albums.count == 1)
        #expect(r.albums[0].id == "1422700834")
        #expect(r.artists.count == 1)
        #expect(r.artists[0].id == "3296287")
        #expect(r.artists[0].name == "Queen")
    }

    @Test("Artwork URL upsized from 100x100 to 600x600")
    func artworkUpsize() async throws {
        let mock = SwitchingHTTPClient()
        mock.responses["song"] = Self.songJSON
        let client = ITunesSearchClient(country: "US", httpClient: mock)
        let r = try await client.search("x")
        #expect(r.tracks[0].artworkURL?.absoluteString.contains("600x600bb.jpg") == true)
    }

    @Test("HTTP error maps to httpError(code)")
    func httpError() async {
        let mock = SwitchingHTTPClient()
        mock.statusCode = 500
        let client = ITunesSearchClient(country: "US", httpClient: mock)
        await #expect(throws: AppleMusicError.self) {
            _ = try await client.search("queen")
        }
    }

    @Test("Malformed JSON maps to invalidResponse")
    func malformed() async {
        let mock = SwitchingHTTPClient()
        mock.responses["song"] = Data("not json".utf8)
        let client = ITunesSearchClient(country: "US", httpClient: mock)
        await #expect(throws: AppleMusicError.invalidResponse) {
            _ = try await client.search("queen")
        }
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd SonoBarKit && bash test.sh --filter ITunesSearchClientTests
```

- [ ] **Step 3: Implement**

Create `SonoBarKit/Sources/SonoBarKit/Services/ITunesSearchClient.swift`:

```swift
// ITunesSearchClient.swift
// SonoBarKit
//
// Public iTunes Search API client. No authentication required.
// https://performance-partners.apple.com/search-api
//
// trackId / collectionId / artistId values returned here are binary-compatible with
// the Sonos Apple Music URI templates used by AppleMusicURIs (verified in the Task 0
// spike via live AddURIToQueue).

import Foundation

public final class ITunesSearchClient: Sendable {
    private let country: String
    private let httpClient: HTTPClientProtocol

    public init(country: String = "US", httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.country = country
        self.httpClient = httpClient
    }

    public func search(_ term: String) async throws -> AppleMusicSearchResults {
        async let songs: [RawResult] = fetchResults(term: term, entity: "song", limit: 25)
        async let albums: [RawResult] = fetchResults(term: term, entity: "album", limit: 25)
        async let artists: [RawResult] = fetchResults(term: term, entity: "musicArtist", limit: 10)

        let (s, a, ar) = try await (songs, albums, artists)
        return AppleMusicSearchResults(
            tracks: s.compactMap(toTrack),
            albums: a.compactMap(toAlbum),
            artists: ar.compactMap(toArtist)
        )
    }

    public func albumTracks(albumId: String) async throws -> [AppleMusicTrack] {
        let results = try await fetchLookup(id: albumId, entity: "song")
        return results.compactMap(toTrack)
    }

    public func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack] {
        let results = try await fetchLookup(id: artistId, entity: "song", limit: 25)
        return results.compactMap(toTrack)
    }

    // MARK: - Private

    private struct SearchResponse: Decodable {
        let resultCount: Int
        let results: [RawResult]
    }

    private struct RawResult: Decodable {
        let wrapperType: String?
        let kind: String?
        let collectionType: String?
        let artistType: String?
        let trackId: Int?
        let collectionId: Int?
        let artistId: Int?
        let artistName: String?
        let collectionName: String?
        let trackName: String?
        let artworkUrl100: String?
        let trackTimeMillis: Int?
        let trackCount: Int?
    }

    private func fetchResults(term: String, entity: String, limit: Int) async throws -> [RawResult] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]
        return try await fetch(url: comps.url!)
    }

    private func fetchLookup(id: String, entity: String, limit: Int = 200) async throws -> [RawResult] {
        var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
        comps.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]
        return try await fetch(url: comps.url!)
    }

    private func fetch(url: URL) async throws -> [RawResult] {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.send(req)
        } catch {
            throw AppleMusicError.networkError
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AppleMusicError.httpError(response.statusCode)
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data).results
        } catch {
            throw AppleMusicError.invalidResponse
        }
    }

    // MARK: - Mappers

    private func toTrack(_ r: RawResult) -> AppleMusicTrack? {
        guard r.kind == "song" || r.wrapperType == "track", let tid = r.trackId else { return nil }
        return AppleMusicTrack(
            id: String(tid),
            title: r.trackName ?? "",
            artist: r.artistName,
            album: r.collectionName,
            albumId: r.collectionId.map(String.init),
            artworkURL: upsizedArtwork(r.artworkUrl100),
            durationSec: r.trackTimeMillis.map { $0 / 1000 }
        )
    }

    private func toAlbum(_ r: RawResult) -> AppleMusicAlbum? {
        guard r.collectionType == "Album" || r.wrapperType == "collection",
              let cid = r.collectionId else { return nil }
        return AppleMusicAlbum(
            id: String(cid),
            title: r.collectionName ?? "",
            artist: r.artistName,
            artworkURL: upsizedArtwork(r.artworkUrl100),
            trackCount: r.trackCount
        )
    }

    private func toArtist(_ r: RawResult) -> AppleMusicArtist? {
        guard r.wrapperType == "artist" || r.artistType != nil, let aid = r.artistId else { return nil }
        return AppleMusicArtist(id: String(aid), name: r.artistName ?? "")
    }

    private func upsizedArtwork(_ urlStr: String?) -> URL? {
        guard let s = urlStr else { return nil }
        let upsized = s.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
        return URL(string: upsized) ?? URL(string: s)
    }
}
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter ITunesSearchClientTests
```
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/ITunesSearchClient.swift \
        SonoBarKit/Tests/SonoBarKitTests/Services/ITunesSearchClientTests.swift
git commit -m "feat(apple-music): add iTunes Search API client with search and lookup"
```

---

## Task 5: AppState — credentials discovery + queue-append

**Files:**
- Modify: `SonoBar/Services/AppState.swift`

- [ ] **Step 1: Locate integration points**

```bash
grep -n "SonosAudibleParams\|sonosAudibleParams\|activeController\|activeClient\|func startDiscovery" SonoBar/Services/AppState.swift | head -25
```

Note exact property/accessor names (`activeController`, `activeClient`, `sonosAudibleParams` etc.). These are used below — rename if the current codebase differs.

- [ ] **Step 2: Add state properties + keys**

Add alongside other stored properties on `AppState`:

```swift
var appleMusicCredentials: AppleMusicCredentials?
var itunesSearchClient: ITunesSearchClient?

private static let appleMusicSnKey = "appleMusicSn"
private static let appleMusicTokenKey = "appleMusicAccountToken"
```

- [ ] **Step 3: Add persistence helpers**

```swift
private static func loadCachedAppleMusicCredentials() -> AppleMusicCredentials? {
    let d = UserDefaults.standard
    guard let token = d.string(forKey: appleMusicTokenKey), !token.isEmpty else { return nil }
    let sn = d.integer(forKey: appleMusicSnKey)
    return AppleMusicCredentials(sn: sn, accountToken: token)
}

private func saveAppleMusicCredentials(_ creds: AppleMusicCredentials) {
    let d = UserDefaults.standard
    d.set(creds.sn, forKey: Self.appleMusicSnKey)
    d.set(creds.accountToken, forKey: Self.appleMusicTokenKey)
}

private func clearAppleMusicCredentials() {
    let d = UserDefaults.standard
    d.removeObject(forKey: Self.appleMusicSnKey)
    d.removeObject(forKey: Self.appleMusicTokenKey)
    appleMusicCredentials = nil
}
```

- [ ] **Step 4: Add discovery + client init**

```swift
/// Loads cached Apple Music credentials or extracts them from the speaker's favorites.
func discoverAppleMusicCredentials() async {
    if let cached = Self.loadCachedAppleMusicCredentials() {
        appleMusicCredentials = cached
    }
    guard let client = activeClient else { return }
    do {
        let favorites = try await client.callAction(
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
        if let didl = favorites["Result"],
           let creds = AppleMusicCredentialsExtractor.extract(favoritesDIDL: didl) {
            appleMusicCredentials = creds
            saveAppleMusicCredentials(creds)
        }
    } catch {
        #if DEBUG
        print("[AppState] Apple Music credentials discovery failed: \(error)")
        #endif
    }
}

func initITunesSearchClient() {
    itunesSearchClient = ITunesSearchClient(country: storefrontCountry())
}

private func storefrontCountry() -> String {
    if let marketplace = sonosAudibleParams?.marketplace {
        switch marketplace.lowercased() {
        case "co.uk": return "GB"
        case "com":   return "US"
        case "de":    return "DE"
        case "fr":    return "FR"
        case "co.jp": return "JP"
        case "ca":    return "CA"
        case "com.au": return "AU"
        default: return "US"
        }
    }
    return "US"
}
```

- [ ] **Step 5: Wire into `startDiscovery`**

At the end of `startDiscovery()`, alongside the other init calls:

```swift
initITunesSearchClient()
await discoverAppleMusicCredentials()
```

- [ ] **Step 6: Add queue-append actions**

```swift
func appendAppleMusicTrack(_ track: AppleMusicTrack) async {
    await appendAppleMusic(.track(track))
}

func appendAppleMusicAlbum(_ album: AppleMusicAlbum) async {
    await appendAppleMusic(.album(album))
}

private func appendAppleMusic(_ item: AppleMusicPlayable) async {
    guard let creds = appleMusicCredentials,
          let controller = activeController else { return }
    let uri: String
    switch item {
    case .track(let t): uri = AppleMusicURIs.trackURI(id: t.id, sn: creds.sn)
    case .album(let a): uri = AppleMusicURIs.albumContainerURI(id: a.id)
    }
    let didl = AppleMusicURIs.didl(for: item, credentials: creds)
    do {
        try await controller.addToQueue(uri: uri, metadata: didl)
    } catch {
        // Speaker rejected our DIDL — likely stale credentials. Force re-discovery.
        clearAppleMusicCredentials()
        #if DEBUG
        print("[AppState] Apple Music append failed: \(error)")
        #endif
    }
}
```

- [ ] **Step 7: Regenerate project and build**

```bash
xcodegen generate
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add SonoBar/Services/AppState.swift SonoBar.xcodeproj/project.pbxproj
git commit -m "feat(apple-music): discover credentials and expose queue-append actions"
```

---

## Task 6: Search view (`AppleMusicSearchView.swift`)

**Files:**
- Create: `SonoBar/Views/AppleMusicSearchView.swift`
- Create: `SonoBar/Views/AppleMusicAlbumDetailView.swift` (stubbed; Task 7 implements)
- Create: `SonoBar/Views/AppleMusicArtistDetailView.swift` (stubbed; Task 7 implements)

- [ ] **Step 1: Create search view**

Create `SonoBar/Views/AppleMusicSearchView.swift`:

```swift
import SwiftUI
import SonoBarKit

struct AppleMusicSearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query: String = ""
    @State private var results: AppleMusicSearchResults?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var activeTask: Task<Void, Never>?
    @State private var selectedAlbum: AppleMusicAlbum?
    @State private var selectedArtist: AppleMusicArtist?

    var body: some View {
        if appState.appleMusicCredentials == nil {
            emptyState
        } else {
            content
                .sheet(item: $selectedAlbum) { a in AppleMusicAlbumDetailView(album: a) }
                .sheet(item: $selectedArtist) { a in AppleMusicArtistDetailView(artist: a) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note").font(.system(size: 32)).foregroundColor(.secondary)
            Text("Favorite one Apple Music track in the Sonos app to enable playback here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) { searchBar; resultsBody }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
            TextField("Search Apple Music", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if query.isEmpty {
            Text("Type to search the Apple Music catalog.")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            VStack(spacing: 8) {
                Text(error).font(.system(size: 11)).foregroundColor(.secondary)
                Button("Retry") { scheduleSearch(query) }.buttonStyle(.plain).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSearching && results == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = results {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !r.tracks.isEmpty  { tracksSection(r.tracks) }
                    if !r.albums.isEmpty  { albumsSection(r.albums) }
                    if !r.artists.isEmpty { artistsSection(r.artists) }
                    if r.tracks.isEmpty && r.albums.isEmpty && r.artists.isEmpty {
                        Text("No results.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    private func tracksSection(_ tracks: [AppleMusicTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tracks").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(tracks) { track in
                    Button { Task { await appState.appendAppleMusicTrack(track) } } label: {
                        rowContent(artwork: track.artworkURL, title: track.title, subtitle: track.artist)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func albumsSection(_ albums: [AppleMusicAlbum]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Albums").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    Button { selectedAlbum = album } label: {
                        rowContent(artwork: album.artworkURL, title: album.title, subtitle: album.artist)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func artistsSection(_ artists: [AppleMusicArtist]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Artists").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(artists) { artist in
                    Button { selectedArtist = artist } label: {
                        rowContent(artwork: nil, title: artist.name, subtitle: nil)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func rowContent(artwork: URL?, title: String, subtitle: String?) -> some View {
        HStack(spacing: 8) {
            artworkThumb(artwork)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                if let s = subtitle {
                    Text(s).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func artworkThumb(_ url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                placeholder: { Color.secondary.opacity(0.15) }
                .frame(width: 32, height: 32).cornerRadius(3)
        } else {
            Color.secondary.opacity(0.15).frame(width: 32, height: 32).cornerRadius(3)
        }
    }

    private func scheduleSearch(_ newQuery: String) {
        activeTask?.cancel()
        errorMessage = nil
        guard !newQuery.isEmpty, let client = appState.itunesSearchClient else {
            results = nil
            return
        }
        activeTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let r = try await client.search(newQuery)
                guard !Task.isCancelled else { return }
                results = r
            } catch {
                guard !Task.isCancelled else { return }
                results = nil
                errorMessage = "Search failed. Try again."
            }
        }
    }
}
```

- [ ] **Step 2: Create stub detail views**

Create `SonoBar/Views/AppleMusicAlbumDetailView.swift`:

```swift
import SwiftUI
import SonoBarKit

struct AppleMusicAlbumDetailView: View {
    let album: AppleMusicAlbum
    var body: some View { Text("Album detail (stub): \(album.title)").padding() }
}
```

Create `SonoBar/Views/AppleMusicArtistDetailView.swift`:

```swift
import SwiftUI
import SonoBarKit

struct AppleMusicArtistDetailView: View {
    let artist: AppleMusicArtist
    var body: some View { Text("Artist detail (stub): \(artist.name)").padding() }
}
```

- [ ] **Step 3: Regenerate Xcode project and build**

```bash
xcodegen generate
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add SonoBar/Views/AppleMusicSearchView.swift \
        SonoBar/Views/AppleMusicAlbumDetailView.swift \
        SonoBar/Views/AppleMusicArtistDetailView.swift \
        SonoBar.xcodeproj/project.pbxproj
git commit -m "feat(apple-music): add search view with debounced iTunes queries"
```

---

## Task 7: Album + artist detail views

**Files:**
- Modify: `SonoBar/Views/AppleMusicAlbumDetailView.swift`
- Modify: `SonoBar/Views/AppleMusicArtistDetailView.swift`

- [ ] **Step 1: Replace album detail stub**

Overwrite `SonoBar/Views/AppleMusicAlbumDetailView.swift`:

```swift
import SwiftUI
import SonoBarKit

struct AppleMusicAlbumDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let album: AppleMusicAlbum

    @State private var tracks: [AppleMusicTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) { header; Divider(); bodyContent }
            .frame(width: 360, height: 480)
            .task { await load() }
    }

    private var header: some View {
        HStack {
            Button("Close") { dismiss() }.buttonStyle(.plain).font(.system(size: 11))
            Spacer()
            VStack(spacing: 1) {
                Text(album.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let a = album.artist {
                    Text(a).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Color.clear.frame(width: 40)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let error = errorMessage, tracks.isEmpty {
            VStack(spacing: 8) {
                Text(error).font(.system(size: 11)).foregroundColor(.secondary)
                Button("Retry") { Task { await load() } }.buttonStyle(.plain).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading && tracks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        Task { await appState.appendAppleMusicAlbum(album) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.badge.plus").font(.system(size: 10))
                            Text("Add all to queue").font(.system(size: 11))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, t in
                            Button {
                                Task { await appState.appendAppleMusicTrack(t) }
                            } label: {
                                trackRow(index: index + 1, track: t)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func trackRow(index: Int, track: AppleMusicTrack) -> some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(track.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer()
            if let d = track.durationSec {
                Text(formatDuration(d))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private func load() async {
        guard let client = appState.itunesSearchClient, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tracks = try await client.albumTracks(albumId: album.id)
        } catch {
            errorMessage = "Couldn't load album. Try again."
        }
    }
}
```

- [ ] **Step 2: Replace artist detail stub**

Overwrite `SonoBar/Views/AppleMusicArtistDetailView.swift`:

```swift
import SwiftUI
import SonoBarKit

struct AppleMusicArtistDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let artist: AppleMusicArtist

    @State private var tracks: [AppleMusicTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { dismiss() }.buttonStyle(.plain).font(.system(size: 11))
                Spacer()
                Text("Top tracks — \(artist.name)")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if let error = errorMessage, tracks.isEmpty {
                VStack(spacing: 8) {
                    Text(error).font(.system(size: 11)).foregroundColor(.secondary)
                    Button("Retry") { Task { await load() } }.buttonStyle(.plain).font(.system(size: 11))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading && tracks.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, t in
                            Button {
                                Task { await appState.appendAppleMusicTrack(t) }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(t.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                        if let album = t.album {
                                            Text(album).font(.system(size: 10))
                                                .foregroundColor(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 480)
        .task { await load() }
    }

    private func load() async {
        guard let client = appState.itunesSearchClient, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tracks = try await client.artistTopTracks(artistId: artist.id)
        } catch {
            errorMessage = "Couldn't load artist. Try again."
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add SonoBar/Views/AppleMusicAlbumDetailView.swift SonoBar/Views/AppleMusicArtistDetailView.swift
git commit -m "feat(apple-music): implement album and artist detail views"
```

---

## Task 8: Wire Apple Music into Browse

**Files:**
- Modify: `SonoBar/Views/BrowseView.swift`

- [ ] **Step 1: Extend segment enum and switch**

In `BrowseView.swift`:

```swift
enum BrowseSegment: String, CaseIterable {
    case recents    = "Recents"
    case plex       = "Plex"
    case audible    = "Audible"
    case appleMusic = "Apple Music"
}
```

Add to the `switch segment` block:

```swift
case .appleMusic:
    AppleMusicSearchView()
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add SonoBar/Views/BrowseView.swift
git commit -m "feat(apple-music): expose Apple Music segment in Browse"
```

---

## Task 9: Cleanup + QA

- [ ] **Step 1: Delete spike scaffolding**

```bash
rm SonoBar/Services/AppleMusicSpike.swift
```

Revert the `#if DEBUG runAppleMusicSpikeIfEligible()` branch in `SonoBar/AppDelegate.swift` (remove the task branch invocation AND the `#if DEBUG` helper method). Then:

```bash
xcodegen generate
```

- [ ] **Step 2: Run full test suite**

```bash
cd SonoBarKit && bash test.sh
```
Expected: all tests pass, no regressions.

- [ ] **Step 3: Release build**

```bash
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Release build 2>&1 | tail -3
```

- [ ] **Step 4: Manual QA on live speaker**

- [ ] Apple Music tab shows search field (credentials cached from prior run, or discovered now).
- [ ] Typing "bohemian rhapsody" after 300ms returns tracks + albums + artists.
- [ ] Tapping a track appends it to the Sonos queue — verify in the Sonos app.
- [ ] Tapping an album opens detail, shows tracks; "Add all to queue" appends full album.
- [ ] Tapping a track row in album detail appends that one track.
- [ ] Tapping an artist opens "Top tracks" — appends work there too.
- [ ] With no Apple Music favorites, empty-state copy is shown instead of search.
- [ ] Airplane-mode the Mac → search shows retry; reconnect → retry works.
- [ ] Restart the app → credentials load from cache (no delay discovering).

- [ ] **Step 5: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove Apple Music spike scaffolding"
```

---

## Summary

9 tasks. Spike already completed and documented in notes; findings directly inform Tasks 2–5. The new approach:

- **Search** = iTunes Search API (public, no auth, no cost).
- **Playback credentials** = extracted from the user's Sonos favorites (one-time, cached, refreshed on failure).
- **Playback** = direct SOAP `AddURIToQueue`, verified live during the spike.

**Explicit non-goals** (from spec): user library browsing, radio stations, editorial recommendations, listening history, library-scoped search, share-URL paste, credentials setup UI.

**Risks:**
- Hard prerequisite: user has favorited one Apple Music item in the Sonos app. Surfaced as empty-state UX, not a flow.
- If Sonos changes DIDL semantics, playback breaks. We mitigate by clearing cached credentials on any SOAP failure and re-extracting on next attempt.
- `AppState.activeClient` / `activeController` / `sonosAudibleParams` accessor names must match — Task 5 Step 1 confirms via grep.
