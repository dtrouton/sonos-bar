# Plex Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add direct Plex Media Server integration to SonoBar for browsing and playing audiobooks and music on Sonos speakers, with bi-directional resume tracking.

**Architecture:** PlexClient (SonoBarKit) talks to the Plex HTTP API for browsing/search/progress. The app layer constructs audio URLs and sends them to Sonos via existing PlaybackController. Plex token stored in Keychain, server IP in UserDefaults.

**Tech Stack:** Swift, SwiftUI, Foundation (URLSession for Plex HTTP), Security.framework (Keychain), Network.framework (mDNS discovery)

**Spec:** `docs/superpowers/specs/2026-03-14-plex-integration-design.md`

---

## File Map

### New Files (SonoBarKit)

| File | Responsibility |
|------|---------------|
| `SonoBarKit/Sources/SonoBarKit/Models/PlexModels.swift` | PlexLibrary, PlexAlbum, PlexTrack structs + JSON parsing |
| `SonoBarKit/Sources/SonoBarKit/Services/PlexClient.swift` | HTTP client for all Plex API endpoints |
| `SonoBarKit/Tests/SonoBarKitTests/Models/PlexModelsTests.swift` | JSON parsing tests for Plex models |
| `SonoBarKit/Tests/SonoBarKitTests/Services/PlexClientTests.swift` | PlexClient endpoint/URL tests |

### New Files (SonoBar app)

| File | Responsibility |
|------|---------------|
| `SonoBar/Services/PlexKeychain.swift` | Read/write Plex token to macOS Keychain |
| `SonoBar/Views/PlexBrowseView.swift` | Main Plex tab: continue listening + library links + search |
| `SonoBar/Views/PlexAlbumListView.swift` | Grid of albums/audiobooks for a library section |
| `SonoBar/Views/PlexTrackListView.swift` | Track list for a single album |
| `SonoBar/Views/PlexSetupView.swift` | First-time setup: server discovery + token entry |

### Modified Files

| File | Changes |
|------|---------|
| `SonoBarKit/Sources/SonoBarKit/Services/PlaybackController.swift` | Add `clearQueue()`, `addToQueue()` |
| `SonoBar/Services/AppState.swift` | PlexClient lifecycle, Plex session tracking, progress reporting |
| `SonoBar/Views/BrowseView.swift` | Add Recents \| Plex segment picker |
| `SonoBar/Views/NowPlayingView.swift` | Update `sourceBadge` for Plex server IP detection |
| `SonoBar.xcodeproj/project.pbxproj` | Add new files to build |

---

## Chunk 1: Plex Models + Client (Data Layer)

### Task 1: Plex Models with JSON Parsing

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Models/PlexModels.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Models/PlexModelsTests.swift`

- [ ] **Step 1: Write test for PlexLibrary JSON parsing**

In `PlexModelsTests.swift`:

```swift
import Testing
@testable import SonoBarKit

@Suite("Plex Models Tests")
struct PlexModelsTests {

    @Test func testPlexLibraryParsesFromJSON() throws {
        let json = """
        {
            "key": "5",
            "title": "Audiobooks",
            "type": "artist"
        }
        """.data(using: .utf8)!

        let lib = try JSONDecoder().decode(PlexLibrary.self, from: json)
        #expect(lib.id == "5")
        #expect(lib.title == "Audiobooks")
        #expect(lib.type == "artist")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SonoBarKit && swift test --filter PlexModelsTests 2>&1 | tail -5`
Expected: FAIL — `PlexLibrary` not defined

- [ ] **Step 3: Implement PlexModels**

In `PlexModels.swift`:

```swift
// SonoBarKit/Sources/SonoBarKit/Models/PlexModels.swift

import Foundation

/// A Plex library section (e.g., "Music", "Audiobooks").
public struct PlexLibrary: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case id = "key"
        case title
        case type
    }
}

/// An album or audiobook in a Plex library.
public struct PlexAlbum: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let artist: String
    public let thumbPath: String?
    public let trackCount: Int
    public let year: Int?
    public let viewOffset: Int?

    private enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case artist = "parentTitle"
        case thumbPath = "thumb"
        case trackCount = "leafCount"
        case year
        case viewOffset
    }
}

/// A track (chapter) in a Plex album or audiobook.
public struct PlexTrack: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let albumTitle: String
    public let artistName: String
    public let duration: Int
    public let viewOffset: Int
    public let index: Int
    public let partKey: String
    public let thumbPath: String?
    public let lastViewedAt: Date?
}

extension PlexTrack: Codable {
    private enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case albumTitle = "parentTitle"
        case artistName = "grandparentTitle"
        case duration
        case viewOffset
        case index
        case thumbPath = "thumb"
        case lastViewedAt
        // Media/Part nested — handled in custom decoder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        albumTitle = try c.decodeIfPresent(String.self, forKey: .albumTitle) ?? ""
        artistName = try c.decodeIfPresent(String.self, forKey: .artistName) ?? ""
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        viewOffset = try c.decodeIfPresent(Int.self, forKey: .viewOffset) ?? 0
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        thumbPath = try c.decodeIfPresent(String.self, forKey: .thumbPath)

        // lastViewedAt is a Unix timestamp
        if let ts = try c.decodeIfPresent(Int.self, forKey: .lastViewedAt) {
            lastViewedAt = Date(timeIntervalSince1970: TimeInterval(ts))
        } else {
            lastViewedAt = nil
        }

        // Extract partKey from nested Media[0].Part[0].key
        struct MediaContainer: Codable {
            let Part: [PartContainer]
        }
        struct PartContainer: Codable {
            let key: String
        }
        enum MediaKeys: String, CodingKey { case Media }
        let root = try decoder.container(keyedBy: MediaKeys.self)
        let media = try root.decodeIfPresent([MediaContainer].self, forKey: .Media)
        partKey = media?.first?.Part.first?.key ?? ""
    }
}

/// Wrapper for Plex API responses that use `MediaContainer`.
public struct PlexResponse<T: Codable>: Codable {
    public let mediaContainer: MediaContainer

    public struct MediaContainer: Codable {
        public let size: Int?
        public let directory: [T]?
        public let metadata: [T]?

        private enum CodingKeys: String, CodingKey {
            case size
            case directory = "Directory"
            case metadata = "Metadata"
        }

        /// Returns whichever array is present (Directory for libraries, Metadata for content).
        public var items: [T] {
            directory ?? metadata ?? []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SonoBarKit && swift test --filter PlexModelsTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Add tests for PlexAlbum and PlexTrack parsing**

Append to `PlexModelsTests.swift`:

```swift
    @Test func testPlexAlbumParsesFromJSON() throws {
        let json = """
        {
            "ratingKey": "3400",
            "title": "Going Postal (Unabridged)",
            "parentTitle": "Terry Pratchett",
            "thumb": "/library/metadata/3400/thumb/123",
            "leafCount": 12,
            "year": 2004
        }
        """.data(using: .utf8)!

        let album = try JSONDecoder().decode(PlexAlbum.self, from: json)
        #expect(album.id == "3400")
        #expect(album.title == "Going Postal (Unabridged)")
        #expect(album.artist == "Terry Pratchett")
        #expect(album.trackCount == 12)
        #expect(album.year == 2004)
    }

    @Test func testPlexTrackParsesFromJSON() throws {
        let json = """
        {
            "ratingKey": "3401",
            "title": "Chapter 1",
            "parentTitle": "Going Postal",
            "grandparentTitle": "Terry Pratchett",
            "duration": 2400000,
            "viewOffset": 1440000,
            "index": 1,
            "thumb": "/library/metadata/3400/thumb/123",
            "lastViewedAt": 1710000000,
            "Media": [{
                "Part": [{
                    "key": "/library/parts/3198/1502763671/file.mp3"
                }]
            }]
        }
        """.data(using: .utf8)!

        let track = try JSONDecoder().decode(PlexTrack.self, from: json)
        #expect(track.id == "3401")
        #expect(track.title == "Chapter 1")
        #expect(track.albumTitle == "Going Postal")
        #expect(track.artistName == "Terry Pratchett")
        #expect(track.duration == 2400000)
        #expect(track.viewOffset == 1440000)
        #expect(track.partKey == "/library/parts/3198/1502763671/file.mp3")
        #expect(track.lastViewedAt != nil)
    }

    @Test func testPlexResponseWrapsItems() throws {
        let json = """
        {
            "MediaContainer": {
                "size": 2,
                "Directory": [
                    {"key": "3", "title": "Music", "type": "artist"},
                    {"key": "5", "title": "Audiobooks", "type": "artist"}
                ]
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PlexResponse<PlexLibrary>.self, from: json)
        #expect(response.mediaContainer.items.count == 2)
        #expect(response.mediaContainer.items[1].title == "Audiobooks")
    }
```

- [ ] **Step 6: Run all model tests**

Run: `cd SonoBarKit && swift test --filter PlexModelsTests 2>&1 | tail -5`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Models/PlexModels.swift SonoBarKit/Tests/SonoBarKitTests/Models/PlexModelsTests.swift
git commit -m "feat: add Plex data models with JSON parsing"
```

---

### Task 2: PlexClient HTTP Client

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/PlexClient.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Services/PlexClientTests.swift`

- [ ] **Step 1: Write test for getLibraries**

In `PlexClientTests.swift`:

```swift
import Testing
@testable import SonoBarKit

@Suite("PlexClient Tests")
struct PlexClientTests {

    private func makeClient(responseJSON: String, statusCode: Int = 200) -> PlexClient {
        let mock = CapturingHTTPClient()
        mock.responseData = Data(responseJSON.utf8)
        mock.responseStatusCode = statusCode
        return PlexClient(host: "192.168.68.78", token: "test-token", httpClient: mock)
    }

    private func mockClient() -> (PlexClient, CapturingHTTPClient) {
        let mock = CapturingHTTPClient()
        let client = PlexClient(host: "192.168.68.78", token: "test-token", httpClient: mock)
        return (client, mock)
    }

    @Test func testGetLibrariesParsesResponse() async throws {
        let client = makeClient(responseJSON: """
        {"MediaContainer":{"size":2,"Directory":[
            {"key":"3","title":"Music","type":"artist"},
            {"key":"5","title":"Audiobooks","type":"artist"}
        ]}}
        """)

        let libs = try await client.getLibraries()
        #expect(libs.count == 2)
        #expect(libs[1].title == "Audiobooks")
    }

    @Test func testGetLibrariesSendsTokenHeader() async throws {
        let (client, mock) = mockClient()
        mock.responseData = Data("""
        {"MediaContainer":{"size":0,"Directory":[]}}
        """.utf8)

        _ = try await client.getLibraries()
        #expect(mock.lastRequest?.value(forHTTPHeaderField: "X-Plex-Token") == "test-token")
        #expect(mock.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(mock.lastRequest?.url?.path == "/library/sections")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SonoBarKit && swift test --filter PlexClientTests 2>&1 | tail -5`
Expected: FAIL — `PlexClient` not defined

- [ ] **Step 3: Implement PlexClient core + getLibraries**

In `PlexClient.swift`:

```swift
// SonoBarKit/Sources/SonoBarKit/Services/PlexClient.swift

import Foundation

/// HTTP client for the Plex Media Server REST API.
public final class PlexClient: Sendable {
    public let host: String
    public let port: Int
    private let token: String
    private let httpClient: HTTPClientProtocol

    public init(host: String, port: Int = 32400, token: String, httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.host = host
        self.port = port
        self.token = token
        self.httpClient = httpClient
    }

    // MARK: - Libraries

    /// Lists all library sections, filtered to audio types (artist/show).
    public func getLibraries() async throws -> [PlexLibrary] {
        let response: PlexResponse<PlexLibrary> = try await get("/library/sections")
        return response.mediaContainer.items
    }

    // MARK: - Albums

    /// Lists albums in a library section.
    public func getAlbums(sectionId: String) async throws -> [PlexAlbum] {
        let response: PlexResponse<PlexAlbum> = try await get("/library/sections/\(sectionId)/all?type=9")
        return response.mediaContainer.items
    }

    // MARK: - Tracks

    /// Lists tracks for an album.
    public func getTracks(albumId: String) async throws -> [PlexTrack] {
        let response: PlexResponse<PlexTrack> = try await get("/library/metadata/\(albumId)/children")
        return response.mediaContainer.items
    }

    // MARK: - On Deck / Continue Listening

    /// Gets in-progress tracks for a library section.
    public func getOnDeck(sectionId: String) async throws -> [PlexTrack] {
        let response: PlexResponse<PlexTrack> = try await get("/library/sections/\(sectionId)/onDeck")
        return response.mediaContainer.items
    }

    // MARK: - Recently Played

    /// Gets recently played albums for a library section.
    public func getRecentlyPlayed(sectionId: String) async throws -> [PlexAlbum] {
        let response: PlexResponse<PlexAlbum> = try await get("/library/sections/\(sectionId)/recentlyViewed")
        return response.mediaContainer.items
    }

    // MARK: - Search

    /// Searches across libraries for albums and tracks.
    public func search(query: String, sectionId: String? = nil) async throws -> [PlexAlbum] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var path = "/hubs/search?query=\(encoded)&type=9"
        if let sectionId { path += "&sectionId=\(sectionId)" }
        let response: PlexResponse<PlexAlbum> = try await get(path)
        return response.mediaContainer.items
    }

    // MARK: - Progress Reporting

    /// Reports playback progress back to Plex.
    public func reportProgress(trackId: String, offsetMs: Int, duration: Int, state: String) async throws {
        let path = "/:/timeline?ratingKey=\(trackId)&key=/library/metadata/\(trackId)&state=\(state)&time=\(offsetMs)&duration=\(duration)"
        _ = try await put(path)
    }

    // MARK: - URL Builders

    /// Constructs a full artwork URL.
    public func thumbURL(path: String) -> URL? {
        URL(string: "http://\(host):\(port)\(path)?X-Plex-Token=\(token)")
    }

    /// Constructs a full audio file URL for Sonos playback.
    public func audioURL(partKey: String) -> URL? {
        URL(string: "http://\(host):\(port)\(partKey)?X-Plex-Token=\(token)")
    }

    // MARK: - Private HTTP

    private func get<T: Codable>(_ path: String) async throws -> T {
        let urlString = "http://\(host):\(port)\(path)"
        guard let url = URL(string: urlString) else {
            throw PlexError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await httpClient.send(request)
        if response.statusCode == 401 {
            throw PlexError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PlexError.httpError(response.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put(_ path: String) async throws {
        let urlString = "http://\(host):\(port)\(path)"
        guard let url = URL(string: urlString) else {
            throw PlexError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.timeoutInterval = 10

        let (_, response) = try await httpClient.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw PlexError.httpError(response.statusCode)
        }
    }
}

/// Errors from the Plex API.
public enum PlexError: Error, Sendable {
    case invalidURL(String)
    case unauthorized
    case httpError(Int)
    case serverUnreachable
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SonoBarKit && swift test --filter PlexClientTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Add tests for getAlbums, getTracks, audioURL**

Append to `PlexClientTests.swift`:

```swift
    @Test func testGetAlbumsUsesCorrectPath() async throws {
        let (client, mock) = mockClient()
        mock.responseData = Data("""
        {"MediaContainer":{"size":1,"Metadata":[
            {"ratingKey":"100","title":"Test Album","parentTitle":"Artist","leafCount":10}
        ]}}
        """.utf8)

        let albums = try await client.getAlbums(sectionId: "5")
        #expect(mock.lastRequest?.url?.path == "/library/sections/5/all")
        #expect(mock.lastRequest?.url?.query?.contains("type=9") == true)
        #expect(albums.count == 1)
        #expect(albums[0].title == "Test Album")
    }

    @Test func testGetTracksUsesCorrectPath() async throws {
        let (client, mock) = mockClient()
        mock.responseData = Data("""
        {"MediaContainer":{"size":1,"Metadata":[
            {"ratingKey":"101","title":"Ch 1","parentTitle":"Book","grandparentTitle":"Author",
             "duration":60000,"viewOffset":0,"index":1,
             "Media":[{"Part":[{"key":"/library/parts/50/1/file.mp3"}]}]}
        ]}}
        """.utf8)

        let tracks = try await client.getTracks(albumId: "100")
        #expect(mock.lastRequest?.url?.path == "/library/metadata/100/children")
        #expect(tracks.count == 1)
        #expect(tracks[0].partKey == "/library/parts/50/1/file.mp3")
    }

    @Test func testAudioURLConstructsCorrectly() {
        let (client, _) = mockClient()
        let url = client.audioURL(partKey: "/library/parts/3198/1502763671/file.mp3")
        #expect(url?.absoluteString == "http://192.168.68.78:32400/library/parts/3198/1502763671/file.mp3?X-Plex-Token=test-token")
    }

    @Test func testUnauthorizedThrowsPlexError() async throws {
        let (client, mock) = mockClient()
        mock.responseData = Data("<html>Unauthorized</html>".utf8)
        mock.responseStatusCode = 401

        await #expect(throws: PlexError.self) {
            _ = try await client.getLibraries()
        }
    }
```

- [ ] **Step 6: Run all PlexClient tests**

Run: `cd SonoBarKit && swift test --filter PlexClientTests 2>&1 | tail -5`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/PlexClient.swift SonoBarKit/Tests/SonoBarKitTests/Services/PlexClientTests.swift
git commit -m "feat: add PlexClient HTTP client for Plex API"
```

---

### Task 3: Queue Management in PlaybackController

**Files:**
- Modify: `SonoBarKit/Sources/SonoBarKit/Services/PlaybackController.swift`
- Modify: `SonoBarKit/Tests/SonoBarKitTests/Services/PlaybackControllerTests.swift` (if exists, otherwise check existing test location)

- [ ] **Step 1: Write tests for clearQueue and addToQueue**

Check existing test file location, then add:

```swift
    @Test func testClearQueueSendsRemoveAllTracks() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "RemoveAllTracksFromQueue", service: .avTransport)
        let controller = PlaybackController(client: SOAPClient(host: "192.168.1.10", httpClient: mock))

        try await controller.clearQueue()
        #expect(mock.lastBodyString?.contains("RemoveAllTracksFromQueue") == true)
    }

    @Test func testAddToQueueSendsCorrectParams() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "AddURIToQueue", service: .avTransport)
        let controller = PlaybackController(client: SOAPClient(host: "192.168.1.10", httpClient: mock))

        try await controller.addToQueue(uri: "http://plex/file.mp3", metadata: "<DIDL/>")
        let body = mock.lastBodyString ?? ""
        #expect(body.contains("AddURIToQueue"))
        #expect(body.contains("http://plex/file.mp3"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SonoBarKit && swift test --filter PlaybackControllerTests 2>&1 | tail -5`
Expected: FAIL — methods not defined

- [ ] **Step 3: Implement clearQueue and addToQueue**

Add to `PlaybackController.swift` after the existing `seekToTrack` method:

```swift
    // MARK: - Queue Management

    /// Removes all tracks from the Sonos queue.
    public func clearQueue() async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "RemoveAllTracksFromQueue",
            params: [("InstanceID", "0")]
        )
    }

    /// Adds a track to the end of the Sonos queue.
    public func addToQueue(uri: String, metadata: String) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "AddURIToQueue",
            params: [
                ("InstanceID", "0"),
                ("EnqueuedURI", uri),
                ("EnqueuedURIMetaData", metadata),
                ("DesiredFirstTrackNumberEnqueued", "0"),
                ("EnqueueAsNext", "0")
            ]
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SonoBarKit && swift test --filter PlaybackControllerTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/PlaybackController.swift SonoBarKit/Tests/SonoBarKitTests/Services/PlaybackControllerTests.swift
git commit -m "feat: add queue management (clearQueue, addToQueue) to PlaybackController"
```

---

## Chunk 2: Configuration + Keychain

### Task 4: Plex Keychain Helper

**Files:**
- Create: `SonoBar/Services/PlexKeychain.swift`

- [ ] **Step 1: Implement PlexKeychain**

```swift
// SonoBar/Services/PlexKeychain.swift

import Foundation
import Security

/// Reads and writes the Plex token to the macOS Keychain.
enum PlexKeychain {
    private static let service = "com.sonobar.plex"
    private static let account = "token"

    /// Reads the stored Plex token, or nil if not set.
    static func getToken() -> String? {
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

    /// Stores the Plex token in the Keychain. Overwrites if exists.
    static func setToken(_ token: String) {
        deleteToken()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Removes the Plex token from the Keychain.
    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SonoBar/Services/PlexKeychain.swift
git commit -m "feat: add PlexKeychain for secure token storage"
```

### Task 5: Plex Setup View

**Files:**
- Create: `SonoBar/Views/PlexSetupView.swift`

- [ ] **Step 1: Implement PlexSetupView**

```swift
// SonoBar/Views/PlexSetupView.swift

import SwiftUI
import Network

struct PlexSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var serverIP = ""
    @State private var token = ""
    @State private var isScanning = false
    @State private var scanResult: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Connect to Plex")
                .font(.system(size: 15, weight: .semibold))

            if isScanning {
                ProgressView("Scanning network...")
                    .controlSize(.small)
            } else if let result = scanResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Found: \(result)")
                        .font(.system(size: 12))
                }
            }

            TextField("Server IP (e.g., 192.168.68.78)", text: $serverIP)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            SecureField("Plex Token", text: $token)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            Text("Find your token: Plex Web → any item → ··· → Get Info → View XML → copy X-Plex-Token from the URL")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("Scan Network") {
                    Task { await scanForServer() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanning)

                Button("Connect") {
                    Task { await connect() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(serverIP.isEmpty || token.isEmpty)
            }

            if appState.plexClient != nil {
                Divider()
                Button("Disconnect", role: .destructive) {
                    appState.disconnectPlex()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .onAppear {
            serverIP = UserDefaults.standard.string(forKey: "plexServerIP") ?? ""
            token = PlexKeychain.getToken() ?? ""
        }
    }

    private func scanForServer() async {
        isScanning = true
        scanResult = nil
        error = nil
        defer { isScanning = false }

        // Try subnet scan on port 32400
        guard let localIP = getLocalIP(),
              let subnet = localIP.split(separator: ".").dropLast().joined(separator: ".") as String? else {
            error = "Can't determine local network"
            return
        }

        for i in 1...254 {
            let ip = "\(subnet).\(i)"
            let urlString = "http://\(ip):32400/identity"
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.3
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let body = String(data: data, encoding: .utf8),
               body.contains("machineIdentifier") {
                serverIP = ip
                scanResult = ip
                return
            }
        }
        error = "No Plex server found on local network"
    }

    private func connect() async {
        error = nil
        let testClient = PlexClient(host: serverIP, token: token)
        do {
            let libs = try await testClient.getLibraries()
            if libs.isEmpty {
                error = "Connected but no libraries found"
                return
            }
            // Save and initialize
            UserDefaults.standard.set(serverIP, forKey: "plexServerIP")
            PlexKeychain.setToken(token)
            appState.connectPlex(host: serverIP, token: token)
        } catch PlexError.unauthorized {
            error = "Invalid token — check and try again"
        } catch {
            self.error = "Can't reach server at \(serverIP)"
        }
    }

    private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee
            guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: addr.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            return String(cString: hostname)
        }
        return nil
    }
}
```

- [ ] **Step 2: Add AppState Plex lifecycle methods**

Add to `AppState.swift` (new section after the Recents section):

```swift
    // MARK: - Plex Integration

    private(set) var plexClient: PlexClient?
    var plexLibraries: [PlexLibrary] = []
    var plexOnDeck: [PlexTrack] = []
    var plexAlbums: [PlexAlbum] = []
    var plexTracks: [PlexTrack] = []
    var plexError: String?
    var isPlexLoading = false

    /// Active Plex session for progress reporting.
    var activePlexTrackId: String?
    var activePlexAlbumId: String?
    private var lastPlexReportTime: Date?

    func connectPlex(host: String, token: String) {
        plexClient = PlexClient(host: host, token: token)
        Task { await loadPlexLibraries() }
    }

    func disconnectPlex() {
        plexClient = nil
        plexLibraries = []
        plexOnDeck = []
        plexAlbums = []
        plexTracks = []
        activePlexTrackId = nil
        UserDefaults.standard.removeObject(forKey: "plexServerIP")
        PlexKeychain.deleteToken()
    }

    func initPlexIfConfigured() {
        guard let host = UserDefaults.standard.string(forKey: "plexServerIP"),
              let token = PlexKeychain.getToken() else { return }
        plexClient = PlexClient(host: host, token: token)
    }

    func loadPlexLibraries() async {
        guard let client = plexClient else { return }
        do {
            plexLibraries = try await client.getLibraries()
                .filter { $0.type == "artist" || $0.type == "show" }
        } catch {
            plexError = "Can't reach Plex server"
        }
    }

    func loadPlexOnDeck() async {
        guard let client = plexClient else { return }
        var allOnDeck: [PlexTrack] = []
        for lib in plexLibraries {
            if let tracks = try? await client.getOnDeck(sectionId: lib.id) {
                allOnDeck.append(contentsOf: tracks)
            }
        }
        plexOnDeck = allOnDeck.sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }
    }

    func loadPlexAlbums(sectionId: String) async {
        guard let client = plexClient else { return }
        isPlexLoading = true
        defer { isPlexLoading = false }
        do {
            plexAlbums = try await client.getAlbums(sectionId: sectionId)
        } catch PlexError.unauthorized {
            plexError = "Plex token expired — update in settings"
        } catch {
            plexError = "Can't reach Plex server"
        }
    }

    func loadPlexTracks(albumId: String) async {
        guard let client = plexClient else { return }
        isPlexLoading = true
        defer { isPlexLoading = false }
        do {
            plexTracks = try await client.getTracks(albumId: albumId)
        } catch {
            plexError = "Failed to load tracks"
        }
    }

    func searchPlex(query: String) async {
        guard let client = plexClient else { return }
        isPlexLoading = true
        defer { isPlexLoading = false }
        do {
            plexAlbums = try await client.search(query: query)
        } catch {
            plexError = "Search failed"
        }
    }
```

- [ ] **Step 3: Call initPlexIfConfigured in startDiscovery**

In `AppState.startDiscovery()`, add after `loadRecents()`:

```swift
        initPlexIfConfigured()
```

- [ ] **Step 4: Commit**

```bash
git add SonoBar/Views/PlexSetupView.swift SonoBar/Services/AppState.swift
git commit -m "feat: add Plex setup view and AppState lifecycle"
```

---

## Chunk 3: Plex Playback + Resume

### Task 6: Plex Playback in AppState

**Files:**
- Modify: `SonoBar/Services/AppState.swift`

- [ ] **Step 1: Add playPlexAlbum and playPlexTrack methods**

Add to AppState's Plex section:

```swift
    /// Plays an entire Plex album/audiobook on the active Sonos speaker.
    func playPlexAlbum(albumId: String, startTrackIndex: Int = 0, seekOffset: Int = 0) async {
        guard let client = plexClient, let controller = activeController else { return }
        do {
            let tracks = try await client.getTracks(albumId: albumId)
            guard !tracks.isEmpty else { return }

            // Clear queue and add all tracks
            try await controller.clearQueue()
            for track in tracks {
                guard let audioURL = client.audioURL(partKey: track.partKey) else { continue }
                let metadata = plexDIDL(track: track)
                try await controller.addToQueue(uri: audioURL.absoluteString, metadata: metadata)
            }

            // Start playback from the right track
            let trackNumber = min(startTrackIndex + 1, tracks.count)
            try await controller.seekToTrack(trackNumber)
            try await controller.play()

            // Track active Plex session
            activePlexTrackId = tracks[startTrackIndex].id
            activePlexAlbumId = albumId

            // If resuming with a time offset, wait for PLAYING then seek
            if seekOffset > 0 {
                try await waitForPlaying()
                let seconds = seekOffset / 1000
                let h = seconds / 3600
                let m = (seconds % 3600) / 60
                let s = seconds % 60
                try await controller.seek(to: String(format: "%d:%02d:%02d", h, m, s))
            }

            await refreshPlayback()
        } catch {
            plexError = "Playback failed: \(error.localizedDescription)"
        }
    }

    /// Resumes a Plex track from its saved viewOffset.
    func resumePlexTrack(_ track: PlexTrack) async {
        guard let client = plexClient else { return }
        // Find which album this track belongs to, get all tracks, find the track's index
        do {
            // Get album ID from track metadata
            let albumTracks = try await client.getTracks(albumId: track.id)
            // If this track IS an album-level item, play from beginning with offset
            // Otherwise find the track index within its album
            await playPlexAlbum(albumId: track.id, seekOffset: track.viewOffset)
        } catch {
            // Fallback: play just this track directly
            await playPlexSingleTrack(track)
        }
    }

    /// Plays a single Plex track on Sonos.
    func playPlexSingleTrack(_ track: PlexTrack) async {
        guard let client = plexClient, let controller = activeController,
              let audioURL = client.audioURL(partKey: track.partKey) else { return }
        do {
            try await controller.clearQueue()
            let metadata = plexDIDL(track: track)
            try await controller.addToQueue(uri: audioURL.absoluteString, metadata: metadata)
            try await controller.seekToTrack(1)
            try await controller.play()

            activePlexTrackId = track.id

            if track.viewOffset > 0 {
                try await waitForPlaying()
                let seconds = track.viewOffset / 1000
                let h = seconds / 3600
                let m = (seconds % 3600) / 60
                let s = seconds % 60
                try await controller.seek(to: String(format: "%d:%02d:%02d", h, m, s))
            }

            await refreshPlayback()
        } catch {
            plexError = "Playback failed: \(error.localizedDescription)"
        }
    }

    /// Waits for Sonos to reach PLAYING state (max 5 seconds).
    private func waitForPlaying() async throws {
        guard let controller = activeController else { return }
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            let state = try await controller.getTransportState()
            if state == .playing { return }
        }
    }

    /// Builds minimal DIDL-Lite metadata for a Plex track.
    private func plexDIDL(track: PlexTrack) -> String {
        let title = track.title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let artist = track.artistName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let album = track.albumTitle
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item><dc:title>\(title)</dc:title>\
        <dc:creator>\(artist)</dc:creator>\
        <upnp:album>\(album)</upnp:album>\
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>\
        </item></DIDL-Lite>
        """
    }
```

- [ ] **Step 2: Add progress reporting**

Add to AppState's Plex section:

```swift
    /// Reports current playback position to Plex (called from refresh timer).
    func reportPlexProgressIfNeeded() async {
        guard let client = plexClient,
              let trackId = activePlexTrackId,
              let controller = activeController else { return }

        // Only report every 30 seconds
        if let last = lastPlexReportTime, Date.now.timeIntervalSince(last) < 30 { return }

        guard let posInfo = try? await controller.getPositionInfo() else { return }
        let elapsed = parseTime(posInfo.elapsed)
        let duration = parseTime(posInfo.duration)
        let state = playbackState.transportState == .playing ? "playing" :
                     playbackState.transportState == .pausedPlayback ? "paused" : "stopped"

        try? await client.reportProgress(
            trackId: trackId,
            offsetMs: elapsed * 1000,
            duration: duration * 1000,
            state: state
        )
        lastPlexReportTime = Date.now
    }

    /// Detects Plex playback from track URI (for externally-started sessions).
    func detectPlexPlayback() {
        guard let uri = playbackState.currentTrack?.uri,
              let host = plexClient?.host,
              uri.contains(host) else {
            return
        }
        // Already tracking this session
        if activePlexTrackId != nil { return }
        // Could extract ratingKey from URI in future — for now just mark as Plex
        // so sourceBadge works correctly
    }
```

- [ ] **Step 3: Hook progress reporting into the refresh timer**

In `NowPlayingView.swift`, update the timer closure to also report Plex progress:

In the existing timer:
```swift
refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    Task {
        await appState.refreshPlayback()
        await appState.reportPlexProgressIfNeeded()
    }
}
```

- [ ] **Step 4: Update sourceBadge to detect Plex server IP**

In `NowPlayingView.swift`, update the `sourceBadge` computed property. After `if uri.contains("plex")`:

```swift
        if let plexHost = appState.plexClient?.host, uri.contains(plexHost) { return "Plex" }
```

- [ ] **Step 5: Commit**

```bash
git add SonoBar/Services/AppState.swift SonoBar/Views/NowPlayingView.swift
git commit -m "feat: add Plex playback, resume, and progress reporting"
```

---

## Chunk 4: Plex Browse UI

### Task 7: PlexBrowseView (Main Plex Tab)

**Files:**
- Create: `SonoBar/Views/PlexBrowseView.swift`

- [ ] **Step 1: Implement PlexBrowseView**

```swift
// SonoBar/Views/PlexBrowseView.swift

import SwiftUI
import SonoBarKit

struct PlexBrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var navigationPath: [PlexNavItem] = []

    enum PlexNavItem: Hashable {
        case library(PlexLibrary)
        case album(PlexAlbum)
        case setup
    }

    var body: some View {
        if appState.plexClient == nil {
            PlexSetupView()
        } else if !navigationPath.isEmpty {
            navigationDestination
        } else {
            plexHome
        }
    }

    private var plexHome: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search audiobooks, music", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        Task {
                            isSearching = true
                            await appState.searchPlex(query: searchText)
                            isSearching = false
                        }
                    }
                if !searchText.isEmpty {
                    Button { searchText = ""; appState.plexAlbums = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if isSearching {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchText.isEmpty && !appState.plexAlbums.isEmpty {
                // Search results
                PlexAlbumListView(albums: appState.plexAlbums) { album in
                    navigationPath.append(.album(album))
                }
            } else if !searchText.isEmpty {
                Text("No results for '\(searchText)'")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Continue Listening
                        if !appState.plexOnDeck.isEmpty {
                            Text("Continue Listening")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(appState.plexOnDeck.prefix(5)) { track in
                                PlexOnDeckRow(track: track) {
                                    Task { await appState.resumePlexTrack(track) }
                                }
                            }

                            Divider().padding(.vertical, 8)
                        }

                        // Libraries
                        Text("Libraries")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)

                        ForEach(appState.plexLibraries) { lib in
                            Button {
                                navigationPath.append(.library(lib))
                            } label: {
                                HStack {
                                    Image(systemName: lib.title.lowercased().contains("audio") ? "book.fill" : "music.note.list")
                                        .font(.system(size: 14))
                                        .frame(width: 24)
                                    Text(lib.title)
                                        .font(.system(size: 13))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // Settings link
                        Divider().padding(.vertical, 8)
                        Button {
                            navigationPath.append(.setup)
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                    .font(.system(size: 12))
                                Text("Plex Settings")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await appState.loadPlexLibraries()
                await appState.loadPlexOnDeck()
            }
        }
    }

    @ViewBuilder
    private var navigationDestination: some View {
        VStack(spacing: 0) {
            // Back button
            Button {
                navigationPath.removeLast()
            } label: {
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10))
                    Text(navigationTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            switch navigationPath.last! {
            case .library(let lib):
                PlexAlbumListView(albums: appState.plexAlbums) { album in
                    navigationPath.append(.album(album))
                }
                .onAppear { Task { await appState.loadPlexAlbums(sectionId: lib.id) } }
            case .album(let album):
                PlexTrackListView(tracks: appState.plexTracks, album: album)
                    .onAppear { Task { await appState.loadPlexTracks(albumId: album.id) } }
            case .setup:
                PlexSetupView()
            }
        }
    }

    private var navigationTitle: String {
        guard let last = navigationPath.last else { return "Plex" }
        switch last {
        case .library(let lib): return lib.title
        case .album(let album): return album.title
        case .setup: return "Settings"
        }
    }
}

/// Row for an on-deck / continue-listening item.
private struct PlexOnDeckRow: View {
    let track: PlexTrack
    let onTap: () -> Void
    @Environment(AppState.self) private var appState

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Thumbnail
                Group {
                    if let thumbPath = track.thumbPath,
                       let url = appState.plexClient?.thumbURL(path: thumbPath) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(nsColor: .controlBackgroundColor)
                        }
                    } else {
                        Color(nsColor: .controlBackgroundColor)
                            .overlay(Image(systemName: "book.fill").foregroundColor(.secondary))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.albumTitle.isEmpty ? track.title : track.albumTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(progressText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progressText: String {
        guard track.duration > 0 else { return "" }
        let pct = Int(Double(track.viewOffset) / Double(track.duration) * 100)
        let mins = track.viewOffset / 60000
        return "\(pct)% · \(mins)m in"
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SonoBar/Views/PlexBrowseView.swift
git commit -m "feat: add PlexBrowseView with continue listening, library navigation, search"
```

### Task 8: PlexAlbumListView + PlexTrackListView

**Files:**
- Create: `SonoBar/Views/PlexAlbumListView.swift`
- Create: `SonoBar/Views/PlexTrackListView.swift`

- [ ] **Step 1: Implement PlexAlbumListView**

```swift
// SonoBar/Views/PlexAlbumListView.swift

import SwiftUI
import SonoBarKit

struct PlexAlbumListView: View {
    let albums: [PlexAlbum]
    var onTap: (PlexAlbum) -> Void
    @Environment(AppState.self) private var appState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        if appState.isPlexLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if albums.isEmpty {
            Text("No items found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(albums) { album in
                        Button { onTap(album) } label: {
                            VStack(spacing: 4) {
                                PlexArtworkView(thumbPath: album.thumbPath)
                                Text(album.title)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                Text(album.artist)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

/// Loads artwork from Plex server.
struct PlexArtworkView: View {
    let thumbPath: String?
    @Environment(AppState.self) private var appState
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay(Image(systemName: "music.note").font(.system(size: 20)).foregroundColor(.secondary))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: thumbPath) {
            guard let path = thumbPath,
                  let url = appState.plexClient?.thumbURL(path: path),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            image = NSImage(data: data)
        }
    }
}
```

- [ ] **Step 2: Implement PlexTrackListView**

```swift
// SonoBar/Views/PlexTrackListView.swift

import SwiftUI
import SonoBarKit

struct PlexTrackListView: View {
    let tracks: [PlexTrack]
    let album: PlexAlbum
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isPlexLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Play all / Resume buttons
                    HStack(spacing: 8) {
                        Button {
                            Task { await appState.playPlexAlbum(albumId: album.id) }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if let resumeTrack = tracks.first(where: { $0.viewOffset > 0 }) {
                            Button {
                                Task {
                                    let idx = tracks.firstIndex(where: { $0.id == resumeTrack.id }) ?? 0
                                    await appState.playPlexAlbum(
                                        albumId: album.id,
                                        startTrackIndex: idx,
                                        seekOffset: resumeTrack.viewOffset
                                    )
                                }
                            } label: {
                                Label("Resume", systemImage: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    ForEach(tracks) { track in
                        Button {
                            let idx = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
                            Task {
                                await appState.playPlexAlbum(
                                    albumId: album.id,
                                    startTrackIndex: idx,
                                    seekOffset: track.viewOffset
                                )
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(track.index)")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    if track.viewOffset > 0 {
                                        ProgressView(value: Double(track.viewOffset), total: Double(track.duration))
                                            .controlSize(.mini)
                                    }
                                }
                                Spacer()
                                Text(formatDuration(track.duration))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let total = ms / 1000
        let m = total / 60
        let s = total % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add SonoBar/Views/PlexAlbumListView.swift SonoBar/Views/PlexTrackListView.swift
git commit -m "feat: add Plex album grid and track list views"
```

---

## Chunk 5: Integration + Wiring

### Task 9: Wire Plex into BrowseView

**Files:**
- Modify: `SonoBar/Views/BrowseView.swift`

- [ ] **Step 1: Add Recents | Plex segment picker**

Replace `BrowseView` to add the Plex segment:

```swift
// Top of file - add segment enum
enum BrowseSegment: String, CaseIterable {
    case recents = "Recents"
    case plex = "Plex"
}
```

Update BrowseView body to include the picker and conditionally show PlexBrowseView:

```swift
    @State private var segment: BrowseSegment = .recents

    // In body, wrap existing content:
    VStack(spacing: 0) {
        // Segment picker
        Picker("", selection: $segment) {
            ForEach(BrowseSegment.allCases, id: \.self) { seg in
                Text(seg.rawValue).tag(seg)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)

        if segment == .plex {
            PlexBrowseView()
        } else {
            // existing recents content (search bar + grid)
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add SonoBar/Views/BrowseView.swift
git commit -m "feat: add Recents | Plex segment to Browse tab"
```

### Task 10: Add New Files to Xcode Project

**Files:**
- Modify: `SonoBar.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add all new SonoBar files to the Xcode project**

Use the same Python script pattern used earlier for QueueListView to add these files:
- `SonoBar/Services/PlexKeychain.swift`
- `SonoBar/Views/PlexBrowseView.swift`
- `SonoBar/Views/PlexAlbumListView.swift`
- `SonoBar/Views/PlexTrackListView.swift`
- `SonoBar/Views/PlexSetupView.swift`

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme SonoBar -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Run all tests**

Run: `cd SonoBarKit && swift test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add SonoBar.xcodeproj/project.pbxproj
git commit -m "chore: add Plex view files to Xcode project"
```

### Task 11: Manual Testing Checklist

- [ ] Launch app, go to Browse → Plex tab
- [ ] Verify setup view appears (if not configured)
- [ ] Enter server IP and token, tap Connect
- [ ] Verify libraries load (Audiobooks, Music)
- [ ] Browse Audiobooks → verify album grid with artwork
- [ ] Tap an audiobook → verify track list with durations
- [ ] Tap a track → verify playback starts on Sonos
- [ ] Check Now Playing shows track title and "Plex" source badge
- [ ] Verify next/previous controls work across tracks
- [ ] Test Continue Listening: play an audiobook partway, stop, check it appears in on-deck
- [ ] Test Resume: tap a continue-listening item, verify it seeks to saved position
- [ ] Test Search: search for an audiobook by title
- [ ] Check Plex Web UI → verify progress was reported back
- [ ] Test error state: disconnect from network, verify error message appears
