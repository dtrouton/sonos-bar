# Apple Music MusicKit Re-architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SonoBar's iTunes Search discovery layer with MusicKit — gaining account-backed catalog search plus My Playlists and My Library — while keeping the proven Sonos playback path (URI/DIDL + extracted account token) unchanged.

**Architecture:** MusicKit is isolated behind a `MusicDiscoveryProviding` protocol (the seam). One real implementation (`MusicKitDiscoveryProvider`) is the only file that imports MusicKit; a `FakeMusicDiscoveryProvider` backs unit tests and previews. All discovery returns the existing `AppleMusic*` value types, so views and `AppState` never touch a MusicKit type. Playback reuses `AppleMusicURIs` + `AppleMusicCredentialsExtractor` + `AppleMusicKeychain` verbatim.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Package Manager, Swift Testing (`import Testing`), MusicKit (macOS 14+). Existing plumbing: `SOAPClient`, `PlaybackController`, `AppState`, `AppleMusicURIs`, `AppleMusicKeychain`.

**Design reference:** [`docs/superpowers/specs/2026-06-03-apple-music-musickit-rearchitecture-design.md`](../specs/2026-06-03-apple-music-musickit-rearchitecture-design.md)

**Spike findings reused unchanged:** [`docs/superpowers/notes/2026-04-19-apple-music-smapi-spike.md`](../notes/2026-04-19-apple-music-smapi-spike.md) — catalog track/album URIs, `sn`, account-token format.

---

## Task 0: Spike — verify library playback on the speaker (REQUIRED FIRST)

This is a **manual investigation task**, not TDD. Its result (`Q1`, `Q2` below) selects between concrete branches in Tasks 2, 6, and 7. Do not skip it — library-playlist playback was never verified and is the single largest risk.

**Files:**
- Create: `docs/superpowers/notes/2026-06-03-apple-music-musickit-spike.md`

- [ ] **Step 1: Pick a real library playlist + library song**

In the Sonos app (or via MusicKit later), identify one Apple Music **library playlist** (id like `p.xxxxxxx`) you have NOT favorited, and one **library song**. Note their IDs. You can read existing favorites' IDs from the speaker with the same `ContentDirectory.Browse FV:2` call `AppState.discoverAppleMusicCredentials()` already uses, to learn the working `sn` and account token.

- [ ] **Step 2: Q1 — try a constructed library-playlist URI**

Using the verified account token and `sn`, construct and `AddURIToQueue` against your speaker (reuse the direct-SOAP approach from the 2026-04-19 spike). Try these container URI candidates for the library playlist `p.ID`, in order, until one returns HTTP 200 with `NumTracksAdded > 0`:

```
x-rincon-cpcontainer:1006206clibraryplaylist%3a{p.ID}
x-rincon-cpcontainer:10fe2064libraryplaylist%3a{p.ID}
x-rincon-cpcontainer:1006206cplaylist%3a{p.ID}
```

DIDL: reuse `AppleMusicURIs.didl` shape with `upnp:class` = `object.container.playlistContainer` and the extracted account token. Record the EXACT working URI prefix and `upnp:class`, or record that none worked.

- [ ] **Step 3: Q2 — confirm a library song resolves to a playable catalog id**

Confirm the chosen library song has a catalog equivalent (any catalog `song:ID` you already know plays — this was verified in the prior spike). The MusicKit-side resolution is tested in Task 3; here you only confirm that a catalog-track URL built from a known catalog id still plays (sanity check that nothing regressed). Record HTTP 200 / `NumTracksAdded=1`.

- [ ] **Step 4: Write the findings note**

Create `docs/superpowers/notes/2026-06-03-apple-music-musickit-spike.md` recording:
- `Q1` result: the working library-playlist URI prefix + `upnp:class`, OR "no constructed library-playlist URI succeeded".
- `Q2` result: catalog-track playback still works (yes/no).
- The `sn` and account token observed (for reference).

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/2026-06-03-apple-music-musickit-spike.md
git commit -m "spike(apple-music): verify library playlist/song playback on speaker"
```

**Decision gate carried forward:**
- **Q1 = success** → implement Task 6 (playlist URI helper) and the Task 7 server-side playlist append. Use the recorded prefix/class.
- **Q1 = failure** → SKIP Task 6; use the Task 7 client-side playlist expansion branch instead.

---

## Task 1: Entitlements & Info.plist prerequisites

**Files:**
- Modify: `SonoBar/Info.plist`
- Modify: `SonoBar/SonoBar.entitlements` (or the entitlements file referenced by `project.yml`)
- Modify: `project.yml` (xcodegen) if capabilities are declared there

- [ ] **Step 1: Enable MusicKit for the bundle ID (manual, Apple portal)**

In developer.apple.com → Certificates, Identifiers & Profiles → your App ID → enable the **MusicKit** App Service. Regenerate/download the provisioning profile if you use an explicit one. (This requires the active Developer Program enrollment.)

- [ ] **Step 2: Add the usage description to Info.plist**

Add to `SonoBar/Info.plist`:

```xml
<key>NSAppleMusicUsageDescription</key>
<string>SonoBar uses Apple Music to browse your library and search the catalog, then plays selections on your Sonos speakers.</string>
```

- [ ] **Step 3: Add MusicKit capability to entitlements**

Ensure the app's entitlements include the MusicKit capability. If `project.yml` declares entitlements, add it there so `xcodegen generate` preserves it. (No `com.apple.developer.*` key is required beyond what the MusicKit capability injects; MusicKit-for-Swift acquires tokens automatically.)

- [ ] **Step 4: Regenerate and build**

```bash
cd /Users/denver/src/sonos
xcodegen generate
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SonoBar/Info.plist SonoBar/SonoBar.entitlements project.yml SonoBar.xcodeproj/project.pbxproj
git commit -m "chore(apple-music): add MusicKit entitlement and usage description"
```

---

## Task 2: Models — `AppleMusicPlaylist` (+ conditional `.playlist` case)

**Files:**
- Modify: `SonoBarKit/Sources/SonoBarKit/Models/AppleMusicModels.swift`
- Modify: `SonoBarKit/Tests/SonoBarKitTests/Models/AppleMusicModelsTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `AppleMusicModelsTests.swift` inside the existing `@Suite` struct:

```swift
@Test("Playlist has expected properties")
func playlistShape() {
    let p = AppleMusicPlaylist(
        id: "p.gek1Rvzfo14X1",
        name: "Christmas (minus Wham!)",
        curatorName: nil,
        artworkURL: nil,
        trackCount: 42,
        isLibrary: true
    )
    #expect(p.id == "p.gek1Rvzfo14X1")
    #expect(p.isLibrary == true)
    #expect(p.trackCount == 42)
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicModelsTests
```
Expected: compile error — `AppleMusicPlaylist` undefined.

- [ ] **Step 3: Add the model**

Add to `AppleMusicModels.swift`:

```swift
public struct AppleMusicPlaylist: Sendable, Identifiable, Equatable {
    public let id: String           // catalog "pl.xxx" or library "p.xxx"
    public let name: String
    public let curatorName: String?
    public let artworkURL: URL?
    public let trackCount: Int?
    public let isLibrary: Bool

    public init(id: String, name: String, curatorName: String?,
                artworkURL: URL?, trackCount: Int?, isLibrary: Bool) {
        self.id = id
        self.name = name
        self.curatorName = curatorName
        self.artworkURL = artworkURL
        self.trackCount = trackCount
        self.isLibrary = isLibrary
    }
}
```

- [ ] **Step 4: (ONLY IF Task 0 Q1 = success) Add `.playlist` to `AppleMusicPlayable`**

In `AppleMusicModels.swift`, extend the enum and its computed accessors:

```swift
public enum AppleMusicPlayable: Sendable, Equatable {
    case track(AppleMusicTrack)
    case album(AppleMusicAlbum)
    case playlist(AppleMusicPlaylist)   // NEW

    public var id: String {
        switch self {
        case .track(let t): return t.id
        case .album(let a): return a.id
        case .playlist(let p): return p.id
        }
    }
    public var title: String {
        switch self {
        case .track(let t): return t.title
        case .album(let a): return a.title
        case .playlist(let p): return p.name
        }
    }
    public var artworkURL: URL? {
        switch self {
        case .track(let t): return t.artworkURL
        case .album(let a): return a.artworkURL
        case .playlist(let p): return p.artworkURL
        }
    }
}
```

If Q1 = failure, leave `AppleMusicPlayable` unchanged (playlists never become a single playable; they expand to tracks in Task 7).

- [ ] **Step 5: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicModelsTests
```
Expected: all model tests pass.

- [ ] **Step 6: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Models/AppleMusicModels.swift \
        SonoBarKit/Tests/SonoBarKitTests/Models/AppleMusicModelsTests.swift
git commit -m "feat(apple-music): add AppleMusicPlaylist model"
```

---

## Task 3: `AppleMusicCatalogIDResolver` — library item → catalog id (pure, TDD)

MusicKit `PlayParameters` is opaque but `Codable`. The provider (Task 5) encodes it to JSON `Data`; this resolver decodes that JSON and returns the Sonos-playable catalog id (or nil). Keeping it pure makes it testable without MusicKit.

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/AppleMusicCatalogIDResolver.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicCatalogIDResolverTests.swift`

- [ ] **Step 1: Write failing tests**

Create `AppleMusicCatalogIDResolverTests.swift`:

```swift
import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicCatalogIDResolver Tests")
struct AppleMusicCatalogIDResolverTests {

    @Test("Catalog song: id is already the catalog id")
    func catalogSong() {
        let json = #"{"id":"1422700837","kind":"song","isLibrary":false}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == "1422700837")
    }

    @Test("Library song with catalogId field resolves to catalog id")
    func librarySongWithCatalogId() {
        let json = #"{"id":"i.abc123","kind":"song","isLibrary":true,"catalogId":"1422700837"}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == "1422700837")
    }

    @Test("Library-only song without catalogId is not playable")
    func libraryOnlySong() {
        let json = #"{"id":"i.abc123","kind":"song","isLibrary":true}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == nil)
    }

    @Test("Malformed JSON returns nil")
    func malformed() {
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data("not json".utf8)) == nil)
    }

    @Test("Nil input returns nil")
    func nilInput() {
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: nil) == nil)
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicCatalogIDResolverTests
```

- [ ] **Step 3: Implement**

Create `AppleMusicCatalogIDResolver.swift`:

```swift
// AppleMusicCatalogIDResolver.swift
// SonoBarKit
//
// Resolves a MusicKit PlayParameters JSON blob to a Sonos-playable catalog song id.
// Catalog items: "id" is already the store id. Library items: prefer "catalogId".
// Library-only (uploaded/matched-without-catalog) items have no catalog id and are
// not playable on Sonos.

import Foundation

public enum AppleMusicCatalogIDResolver {

    private struct PlayParametersJSON: Decodable {
        let id: String?
        let catalogId: String?
        let isLibrary: Bool?
    }

    /// Returns the catalog song id usable in `AppleMusicURIs.trackURI`, or nil if none.
    public static func catalogID(playParametersJSON: Data?) -> String? {
        guard let data = playParametersJSON,
              let pp = try? JSONDecoder().decode(PlayParametersJSON.self, from: data)
        else { return nil }

        if let catalogId = pp.catalogId, !catalogId.isEmpty {
            return catalogId
        }
        // Catalog item: id is the store id. Library item without catalogId: not playable.
        if pp.isLibrary == true { return nil }
        if let id = pp.id, !id.isEmpty, id.allSatisfy(\.isNumber) { return id }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicCatalogIDResolverTests
```
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/AppleMusicCatalogIDResolver.swift \
        SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicCatalogIDResolverTests.swift
git commit -m "feat(apple-music): resolve library playParameters to catalog id"
```

---

## Task 4: `MusicDiscoveryProviding` protocol + `FakeMusicDiscoveryProvider`

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/MusicDiscoveryProviding.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Support/FakeMusicDiscoveryProvider.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Support/FakeMusicDiscoveryProviderTests.swift`

- [ ] **Step 1: Define the protocol + auth enum**

Create `MusicDiscoveryProviding.swift`:

```swift
// MusicDiscoveryProviding.swift
// SonoBarKit
//
// The seam isolating MusicKit from the rest of the app. The only concrete
// implementation that imports MusicKit is MusicKitDiscoveryProvider; tests and
// previews use a fake. All methods return the app's own AppleMusic* value types.

import Foundation

public enum MusicAuthStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

public protocol MusicDiscoveryProviding: Sendable {
    func currentAuthStatus() -> MusicAuthStatus
    func requestAuthorization() async -> MusicAuthStatus

    func search(_ term: String) async throws -> AppleMusicSearchResults
    func libraryPlaylists() async throws -> [AppleMusicPlaylist]
    func libraryAlbums() async throws -> [AppleMusicAlbum]
    func librarySongs() async throws -> [AppleMusicTrack]
    func playlistTracks(playlistId: String) async throws -> [AppleMusicTrack]
    func albumTracks(albumId: String) async throws -> [AppleMusicTrack]
    func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack]
}
```

- [ ] **Step 2: Write the fake (in test target) + a test proving it conforms**

Create `FakeMusicDiscoveryProvider.swift`:

```swift
import Foundation
@testable import SonoBarKit

/// Scriptable MusicDiscoveryProviding for unit tests and AppState wiring.
final class FakeMusicDiscoveryProvider: MusicDiscoveryProviding, @unchecked Sendable {
    var authStatus: MusicAuthStatus = .authorized
    var searchResult: AppleMusicSearchResults =
        AppleMusicSearchResults(tracks: [], albums: [], artists: [])
    var playlists: [AppleMusicPlaylist] = []
    var albums: [AppleMusicAlbum] = []
    var songs: [AppleMusicTrack] = []
    var playlistTracksById: [String: [AppleMusicTrack]] = [:]
    var albumTracksById: [String: [AppleMusicTrack]] = [:]
    var artistTopTracksById: [String: [AppleMusicTrack]] = [:]
    var errorToThrow: AppleMusicError?

    func currentAuthStatus() -> MusicAuthStatus { authStatus }
    func requestAuthorization() async -> MusicAuthStatus { authStatus }

    func search(_ term: String) async throws -> AppleMusicSearchResults {
        if let e = errorToThrow { throw e }
        return searchResult
    }
    func libraryPlaylists() async throws -> [AppleMusicPlaylist] {
        if let e = errorToThrow { throw e }
        return playlists
    }
    func libraryAlbums() async throws -> [AppleMusicAlbum] {
        if let e = errorToThrow { throw e }
        return albums
    }
    func librarySongs() async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return songs
    }
    func playlistTracks(playlistId: String) async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return playlistTracksById[playlistId] ?? []
    }
    func albumTracks(albumId: String) async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return albumTracksById[albumId] ?? []
    }
    func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return artistTopTracksById[artistId] ?? []
    }
}
```

Create `FakeMusicDiscoveryProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import SonoBarKit

@Suite("FakeMusicDiscoveryProvider Tests")
struct FakeMusicDiscoveryProviderTests {

    @Test("Returns scripted playlists")
    func returnsPlaylists() async throws {
        let fake = FakeMusicDiscoveryProvider()
        fake.playlists = [AppleMusicPlaylist(id: "p.1", name: "Mix", curatorName: nil,
                                             artworkURL: nil, trackCount: 3, isLibrary: true)]
        let result = try await fake.libraryPlaylists()
        #expect(result.count == 1)
        #expect(result[0].id == "p.1")
    }

    @Test("Throws scripted error")
    func throwsError() async {
        let fake = FakeMusicDiscoveryProvider()
        fake.errorToThrow = .networkError
        await #expect(throws: AppleMusicError.networkError) {
            _ = try await fake.search("x")
        }
    }
}
```

- [ ] **Step 3: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter FakeMusicDiscoveryProvider
```
Expected: 2 tests pass (proves protocol + fake compile and behave).

- [ ] **Step 4: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/MusicDiscoveryProviding.swift \
        SonoBarKit/Tests/SonoBarKitTests/Support/FakeMusicDiscoveryProvider.swift \
        SonoBarKit/Tests/SonoBarKitTests/Support/FakeMusicDiscoveryProviderTests.swift
git commit -m "feat(apple-music): add MusicDiscoveryProviding seam and test fake"
```

---

## Task 5: `MusicKitDiscoveryProvider` — the real implementation (no unit tests)

This is the only file importing MusicKit. It is NOT unit-tested (MusicKit requests need a live account/entitlement); it is covered by Task 11 manual QA, exactly as `ITunesSearchClient`'s live calls were.

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/MusicKitDiscoveryProvider.swift`

- [ ] **Step 1: Implement the provider**

Create `MusicKitDiscoveryProvider.swift`:

```swift
// MusicKitDiscoveryProvider.swift
// SonoBarKit
//
// THE ONLY FILE THAT IMPORTS MusicKit. Wraps MusicKit catalog search + library
// requests into the app's AppleMusic* value types. Not unit-tested — exercised by
// manual QA on a real Mac with a signed-in Apple Music account.

import Foundation
import MusicKit

public final class MusicKitDiscoveryProvider: MusicDiscoveryProviding, @unchecked Sendable {

    public init() {}

    public func currentAuthStatus() -> MusicAuthStatus {
        Self.map(MusicAuthorization.currentStatus)
    }

    public func requestAuthorization() async -> MusicAuthStatus {
        Self.map(await MusicAuthorization.request())
    }

    private static func map(_ status: MusicAuthorization.Status) -> MusicAuthStatus {
        switch status {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    // MARK: - Catalog search

    public func search(_ term: String) async throws -> AppleMusicSearchResults {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self])
        request.limit = 25
        let response: MusicCatalogSearchResponse
        do {
            response = try await request.response()
        } catch {
            throw AppleMusicError.networkError
        }
        return AppleMusicSearchResults(
            tracks: response.songs.map(Self.track(from:)),
            albums: response.albums.map(Self.album(from:)),
            artists: response.artists.map { AppleMusicArtist(id: $0.id.rawValue, name: $0.name) }
        )
    }

    // MARK: - Library

    public func libraryPlaylists() async throws -> [AppleMusicPlaylist] {
        do {
            let response = try await MusicLibraryRequest<Playlist>().response()
            return response.items.map(Self.playlist(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func libraryAlbums() async throws -> [AppleMusicAlbum] {
        do {
            let response = try await MusicLibraryRequest<Album>().response()
            return response.items.map(Self.album(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func librarySongs() async throws -> [AppleMusicTrack] {
        do {
            let response = try await MusicLibraryRequest<Song>().response()
            return response.items.map(Self.track(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func playlistTracks(playlistId: String) async throws -> [AppleMusicTrack] {
        do {
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, equalTo: MusicItemID(playlistId))
            guard let playlist = try await request.response().items.first else { return [] }
            let detailed = try await playlist.with([.tracks])
            return (detailed.tracks ?? []).map(Self.track(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func albumTracks(albumId: String) async throws -> [AppleMusicTrack] {
        do {
            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(albumId))
            guard let album = try await request.response().items.first else { return [] }
            let detailed = try await album.with([.tracks])
            return (detailed.tracks ?? []).map(Self.track(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack] {
        do {
            let request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(artistId))
            guard let artist = try await request.response().items.first else { return [] }
            let detailed = try await artist.with([.topSongs])
            return (detailed.topSongs ?? []).map(Self.track(from:))
        } catch { throw AppleMusicError.networkError }
    }

    // MARK: - Mappers

    private static func track(from song: Song) -> AppleMusicTrack {
        AppleMusicTrack(
            id: catalogID(for: song) ?? song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            albumId: nil,
            artworkURL: song.artwork?.url(width: 600, height: 600),
            durationSec: song.duration.map { Int($0) }
        )
    }

    private static func track(from track: Track) -> AppleMusicTrack {
        switch track {
        case .song(let s): return self.track(from: s)
        case .musicVideo(let v):
            return AppleMusicTrack(id: v.id.rawValue, title: v.title, artist: v.artistName,
                                   album: v.albumTitle, albumId: nil,
                                   artworkURL: v.artwork?.url(width: 600, height: 600),
                                   durationSec: v.duration.map { Int($0) })
        @unknown default:
            return AppleMusicTrack(id: "", title: "", artist: nil, album: nil,
                                   albumId: nil, artworkURL: nil, durationSec: nil)
        }
    }

    private static func album(from album: Album) -> AppleMusicAlbum {
        AppleMusicAlbum(
            id: album.id.rawValue,
            title: album.title,
            artist: album.artistName,
            artworkURL: album.artwork?.url(width: 600, height: 600),
            trackCount: album.trackCount
        )
    }

    private static func playlist(from playlist: Playlist) -> AppleMusicPlaylist {
        AppleMusicPlaylist(
            id: playlist.id.rawValue,
            name: playlist.name,
            curatorName: playlist.curatorName,
            artworkURL: playlist.artwork?.url(width: 600, height: 600),
            trackCount: nil,
            isLibrary: true
        )
    }

    /// Encodes the song's PlayParameters to JSON and resolves the Sonos-playable catalog id.
    private static func catalogID(for song: Song) -> String? {
        guard let pp = song.playParameters,
              let data = try? JSONEncoder().encode(pp) else { return nil }
        return AppleMusicCatalogIDResolver.catalogID(playParametersJSON: data)
    }
}
```

- [ ] **Step 2: Build the package**

```bash
cd SonoBarKit && swift build 2>&1 | tail -5
```
Expected: builds. If a MusicKit symbol name differs on the local SDK (e.g. `curatorName`, `MusicCatalogResourceRequest`), fix to match the SDK — the surrounding mapper structure stays the same.

- [ ] **Step 3: Run the full package test suite (no new tests, confirm no regressions)**

```bash
cd SonoBarKit && bash test.sh 2>&1 | tail -5
```
Expected: all existing + new tests pass; provider has no tests by design.

- [ ] **Step 4: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/MusicKitDiscoveryProvider.swift
git commit -m "feat(apple-music): MusicKit-backed discovery provider"
```

---

## Task 6: Playlist URI helper — ONLY IF Task 0 Q1 = SUCCESS

If Q1 failed, SKIP this task entirely and use the client-side expansion branch in Task 7.

**Files:**
- Modify: `SonoBarKit/Sources/SonoBarKit/Services/AppleMusicURIs.swift`
- Modify: `SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicURIsTests.swift`

- [ ] **Step 1: Write failing tests (substitute the prefix/class recorded in Task 0)**

Add to `AppleMusicURIsTests.swift`. Replace `1006206clibraryplaylist` and `object.container.playlistContainer` with the EXACT values recorded in the Task 0 spike note:

```swift
@Test("Library playlist container URI uses verified prefix")
func playlistURI() {
    #expect(AppleMusicURIs.playlistContainerURI(id: "p.gek1Rvzfo14X1", isLibrary: true) ==
            "x-rincon-cpcontainer:1006206clibraryplaylist%3ap.gek1Rvzfo14X1")
}

@Test("DIDL for playlist uses container class and account token")
func didlPlaylist() {
    let creds = AppleMusicCredentials(sn: 19, accountToken: "890cb54f")
    let p = AppleMusicPlaylist(id: "p.gek1Rvzfo14X1", name: "Xmas", curatorName: nil,
                               artworkURL: nil, trackCount: 5, isLibrary: true)
    let didl = AppleMusicURIs.didl(for: .playlist(p), credentials: creds)
    #expect(didl.contains("object.container.playlistContainer"))
    #expect(didl.contains("890cb54f"))
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicURIsTests
```

- [ ] **Step 3: Implement (substitute recorded prefix/class)**

In `AppleMusicURIs.swift`, add the helper as a literal of the EXACT prefix recorded in the Task 0 spike note (do not reconstruct it from parts — write the verified string directly), then extend the three `switch` functions to handle `.playlist`:

```swift
public static func playlistContainerURI(id: String, isLibrary: Bool) -> String {
    // Prefixes recorded in the 2026-06-03 spike note. Substitute the exact verified values.
    isLibrary
        ? "x-rincon-cpcontainer:1006206clibraryplaylist%3a\(id)"
        : "x-rincon-cpcontainer:1006206cplaylist%3a\(id)"
}
```

Extend the switches:

```swift
private static func upnpClass(for item: AppleMusicPlayable) -> String {
    switch item {
    case .track: return "object.item.audioItem.musicTrack"
    case .album: return "object.container.album.musicAlbum"
    case .playlist: return "object.container.playlistContainer"
    }
}

private static func itemID(for item: AppleMusicPlayable) -> String {
    switch item {
    case .track(let t): return "10032028song%3a\(t.id)"
    case .album(let a): return "1004206calbum%3a\(a.id)"
    case .playlist(let p): return "1006206clibraryplaylist%3a\(p.id)"
    }
}

private static func parentID(for item: AppleMusicPlayable) -> String {
    switch item {
    case .track: return "00020000song:"
    case .album: return "00020000album:"
    case .playlist: return "00020000playlist:"
    }
}
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
cd SonoBarKit && bash test.sh --filter AppleMusicURIsTests
```
Expected: all URI tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/AppleMusicURIs.swift \
        SonoBarKit/Tests/SonoBarKitTests/Services/AppleMusicURIsTests.swift
git commit -m "feat(apple-music): add verified library playlist container URI"
```

---

## Task 7: AppState integration — swap engine, auth gating, playlist append

**Files:**
- Modify: `SonoBar/Services/AppState.swift`

- [ ] **Step 1: Replace the iTunes client property + init**

Replace `var itunesSearchClient: ITunesSearchClient?` (line ~1248) with:

```swift
var musicDiscovery: MusicDiscoveryProviding = MusicKitDiscoveryProvider()
var appleMusicAuthStatus: MusicAuthStatus = .notDetermined
```

Delete `var itunesSearchClient: ITunesSearchClient?`, `func initITunesSearchClient()`, and `private func storefrontCountry() -> String` entirely. (MusicKit infers storefront from the account.)

- [ ] **Step 2: Replace the startup wiring**

At the `startDiscovery()` site (lines ~110-111), replace:

```swift
initITunesSearchClient()
await discoverAppleMusicCredentials()
```

with:

```swift
await discoverAppleMusicCredentials()
if appleMusicCredentials != nil {
    appleMusicAuthStatus = await musicDiscovery.requestAuthorization()
}
```

(Authorization is requested only after the token gate is satisfied, matching the "gate everything until token exists" decision.)

- [ ] **Step 3: Add the playlist append action**

**IF Task 0 Q1 = SUCCESS**, add a server-side append mirroring `appendAppleMusicAlbum`:

```swift
func appendAppleMusicPlaylist(_ playlist: AppleMusicPlaylist) async {
    await appendAppleMusic(.playlist(playlist))
}
```

and extend the `uri` switch inside `appendAppleMusic(_:)`:

```swift
case .playlist(let p): uri = AppleMusicURIs.playlistContainerURI(id: p.id, isLibrary: p.isLibrary)
```

**IF Task 0 Q1 = FAILURE**, add a client-side expansion instead (no `.playlist` enum case exists):

```swift
func appendAppleMusicPlaylist(_ playlist: AppleMusicPlaylist) async {
    let tracks: [AppleMusicTrack]
    do {
        tracks = try await musicDiscovery.playlistTracks(playlistId: playlist.id)
    } catch {
        appleMusicError = "Couldn't load playlist tracks. Try again."
        return
    }
    let playable = tracks.filter { Int($0.id) != nil }   // only catalog-resolvable tracks
    if playable.isEmpty {
        appleMusicError = "None of this playlist's tracks are available to stream on Sonos."
        return
    }
    for track in playable {
        await appendAppleMusicTrack(track)
    }
}
```

- [ ] **Step 4: Build the package (app build is expected to stay red until Task 8)**

```bash
cd SonoBarKit && swift build 2>&1 | tail -5
```
Expected: the package builds. The **app** target will NOT compile yet — `AppleMusicSearchView`/`AppleMusicAlbumDetailView`/`AppleMusicArtistDetailView` still reference the now-deleted `itunesSearchClient`; Task 8 repoints them. This is the one intentional red window in the plan. Verify the only app-target errors are `itunesSearchClient` references; fix any other (unexpected) errors now.

- [ ] **Step 5: Commit**

```bash
git add SonoBar/Services/AppState.swift SonoBar.xcodeproj/project.pbxproj
git commit -m "feat(apple-music): wire MusicKit discovery, auth gating, playlist append"
```

---

## Task 8: Search view — auth states + library/playlists sections

**Files:**
- Modify: `SonoBar/Views/AppleMusicSearchView.swift`

- [ ] **Step 1: Update the gate to layer auth on top of credentials**

Replace the top-level `body` branch (currently `if appState.appleMusicCredentials == nil { emptyState } else { content ... }`) with a three-state gate:

```swift
var body: some View {
    if appState.appleMusicCredentials == nil {
        emptyState   // existing "favorite one track" copy
    } else if appState.appleMusicAuthStatus == .denied {
        authDeniedState
    } else {
        content
            .sheet(item: $selectedAlbum) { a in AppleMusicAlbumDetailView(album: a) }
            .sheet(item: $selectedArtist) { a in AppleMusicArtistDetailView(artist: a) }
            .sheet(item: $selectedPlaylist) { p in AppleMusicPlaylistDetailView(playlist: p) }
    }
}

private var authDeniedState: some View {
    VStack(spacing: 10) {
        Image(systemName: "lock.fill").font(.system(size: 32)).foregroundColor(.secondary)
        Text("Allow Apple Music access in System Settings to browse your library.")
            .font(.system(size: 12)).foregroundColor(.secondary)
            .multilineTextAlignment(.center).padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

Add `@State private var selectedPlaylist: AppleMusicPlaylist?` alongside the existing `@State` selections.

- [ ] **Step 2: Add a segmented sub-mode (Search / Playlists / Library) above results**

Add `@State private var mode: AMMode = .search` and an enum near the top of the file:

```swift
private enum AMMode: String, CaseIterable, Identifiable {
    case search = "Search", playlists = "Playlists", library = "Library"
    var id: String { rawValue }
}
```

Insert a `Picker` in `content` above `resultsBody`:

```swift
Picker("", selection: $mode) {
    ForEach(AMMode.allCases) { Text($0.rawValue).tag($0) }
}
.pickerStyle(.segmented)
.padding(.horizontal, 12).padding(.bottom, 6)
```

Render the body by mode: `.search` keeps the existing search bar + `resultsBody`; `.playlists` shows a list loaded from `appState.musicDiscovery.libraryPlaylists()`; `.library` shows the user's saved **albums** then **songs** (two labeled sub-sections, matching the design's "Library albums/songs" scope) loaded from `libraryAlbums()` and `librarySongs()`. Reuse the existing `rowContent(...)` and `artworkThumb(...)` helpers. Playlist rows set `selectedPlaylist = playlist`; album rows set `selectedAlbum = album`; song rows append directly via `Task { await appState.appendAppleMusicTrack(song) }` (a library song whose `id` is non-numeric, i.e. unresolved to a catalog id, is rendered disabled — `.disabled(Int(song.id) == nil)`).

```swift
@State private var libraryPlaylists: [AppleMusicPlaylist] = []
@State private var libraryAlbums: [AppleMusicAlbum] = []
@State private var librarySongs: [AppleMusicTrack] = []
@State private var libraryError: String?

private func loadLibrary() async {
    do {
        async let p = appState.musicDiscovery.libraryPlaylists()
        async let a = appState.musicDiscovery.libraryAlbums()
        async let s = appState.musicDiscovery.librarySongs()
        libraryPlaylists = try await p
        libraryAlbums = try await a
        librarySongs = try await s
        libraryError = nil
    } catch {
        libraryError = "Couldn't load your library. Retry."
    }
}
```

Trigger `loadLibrary()` via `.task(id: mode)` when `mode != .search`. Show `ProgressView` while empty, `libraryError` with a Retry button on failure, else the rows.

- [ ] **Step 3: Repoint the existing album + artist detail views to `musicDiscovery`**

`AppleMusicAlbumDetailView.swift` and `AppleMusicArtistDetailView.swift` currently call `appState.itunesSearchClient` (the property deleted in Task 7). Update both `load()` functions:

In `AppleMusicAlbumDetailView.swift`, replace:

```swift
guard let client = appState.itunesSearchClient, !isLoading else { return }
isLoading = true
errorMessage = nil
defer { isLoading = false }
do {
    tracks = try await client.albumTracks(albumId: album.id)
} catch {
    errorMessage = "Couldn't load album. Try again."
}
```

with:

```swift
guard !isLoading else { return }
isLoading = true
errorMessage = nil
defer { isLoading = false }
do {
    tracks = try await appState.musicDiscovery.albumTracks(albumId: album.id)
} catch {
    errorMessage = "Couldn't load album. Try again."
}
```

In `AppleMusicArtistDetailView.swift`, apply the same change, replacing `client.artistTopTracks(artistId: artist.id)` with `appState.musicDiscovery.artistTopTracks(artistId: artist.id)` and removing the `guard let client = appState.itunesSearchClient` clause (keep `guard !isLoading`).

- [ ] **Step 4: Build**

```bash
cd /Users/denver/src/sonos
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add SonoBar/Views/AppleMusicSearchView.swift SonoBar/Views/AppleMusicAlbumDetailView.swift \
        SonoBar/Views/AppleMusicArtistDetailView.swift SonoBar.xcodeproj/project.pbxproj
git commit -m "feat(apple-music): add auth states, library browsing, repoint detail views to MusicKit"
```

---

## Task 9: Playlist detail view

**Files:**
- Create: `SonoBar/Views/AppleMusicPlaylistDetailView.swift`

- [ ] **Step 1: Create the view (modeled on AppleMusicAlbumDetailView)**

Create `AppleMusicPlaylistDetailView.swift`:

```swift
import SwiftUI
import SonoBarKit

struct AppleMusicPlaylistDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let playlist: AppleMusicPlaylist

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
            Text(playlist.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
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
                    Button { Task { await appState.appendAppleMusicPlaylist(playlist) } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.badge.plus").font(.system(size: 10))
                            Text("Add all to queue").font(.system(size: 11))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15)).cornerRadius(14)
                    }
                    .buttonStyle(.plain).padding(.vertical, 8)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, t in
                            let playable = Int(t.id) != nil
                            Button { Task { await appState.appendAppleMusicTrack(t) } } label: {
                                trackRow(index: index + 1, track: t, playable: playable)
                            }
                            .buttonStyle(.plain).disabled(!playable)
                        }
                    }
                }
            }
        }
    }

    private func trackRow(index: Int, track: AppleMusicTrack, playable: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(index)").font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary).frame(width: 24, alignment: .trailing)
            Text(track.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .foregroundColor(playable ? .primary : .secondary)
            if !playable {
                Text("Not on Sonos").font(.system(size: 9)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tracks = try await appState.musicDiscovery.playlistTracks(playlistId: playlist.id)
        } catch {
            errorMessage = "Couldn't load playlist. Try again."
        }
    }
}
```

- [ ] **Step 2: Regenerate + build**

```bash
cd /Users/denver/src/sonos && xcodegen generate
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add SonoBar/Views/AppleMusicPlaylistDetailView.swift SonoBar.xcodeproj/project.pbxproj
git commit -m "feat(apple-music): add playlist detail view"
```

---

## Task 10: Remove the iTunes Search layer

**Files:**
- Delete: `SonoBarKit/Sources/SonoBarKit/Services/ITunesSearchClient.swift`
- Delete: `SonoBarKit/Tests/SonoBarKitTests/Services/ITunesSearchClientTests.swift`

- [ ] **Step 1: Confirm no remaining references**

```bash
cd /Users/denver/src/sonos
grep -rn "ITunesSearchClient\|itunesSearchClient\|storefrontCountry\|initITunesSearchClient" SonoBar SonoBarKit/Sources SonoBarKit/Tests
```
Expected: no matches (Tasks 7-9 removed them). If any remain, fix them before deleting.

- [ ] **Step 2: Delete the files**

```bash
git rm SonoBarKit/Sources/SonoBarKit/Services/ITunesSearchClient.swift \
       SonoBarKit/Tests/SonoBarKitTests/Services/ITunesSearchClientTests.swift
```

- [ ] **Step 3: Full package test + app build**

```bash
cd SonoBarKit && bash test.sh 2>&1 | tail -5
cd /Users/denver/src/sonos && xcodegen generate
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | tail -3
```
Expected: all tests pass; BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(apple-music): remove iTunes Search layer, superseded by MusicKit"
```

---

## Task 11: Verification & manual QA

**Files:** none (verification only)

- [ ] **Step 1: Full test suite + release build**

```bash
cd SonoBarKit && bash test.sh 2>&1 | tail -5
cd /Users/denver/src/sonos
xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Release build 2>&1 | tail -3
```
Expected: all tests pass; BUILD SUCCEEDED.

- [ ] **Step 2: Manual QA on a real Mac + live speaker**

Run the app and verify:
- [ ] With no Apple Music favorite/token → "favorite one track" empty state (unchanged).
- [ ] First launch with a token → macOS prompts for Apple Music access.
- [ ] Deny → "Allow Apple Music access in System Settings" state; granting in Settings + relaunch → browsing appears.
- [ ] Search "bohemian rhapsody" → tracks/albums/artists; tapping a track queues it (verify in Sonos app).
- [ ] Playlists tab lists your Apple Music playlists; opening one shows tracks; "Add all to queue" works (server-side if Q1 succeeded, per-track if not).
- [ ] Library tab lists saved albums AND saved songs; opening an album + "Add all" works; tapping a library song queues it.
- [ ] A library-only/uploaded song appears disabled with "Not on Sonos".
- [ ] Stale-token path: if append fails, credentials clear + the "favorite a track to refresh" message shows.
- [ ] Relaunch → token loads from Keychain (no re-favoriting needed).

- [ ] **Step 3: Update the stale TODO note**

`TODO-apple-music.md` describes the original (never-shipped) MusicKit-only plan and is now superseded. Replace its body with a one-line pointer to this plan + the design spec, or delete it.

```bash
git rm TODO-apple-music.md
git commit -m "docs(apple-music): remove superseded TODO note"
```

- [ ] **Step 4: Finalize**

Use the superpowers:finishing-a-development-branch skill to decide merge/PR for `feat/apple-music-musickit`.

---

## Summary

11 tasks. Task 0 (spike) is a required gate whose result selects concrete branches in Tasks 2, 6, and 7 — both branches are fully specified, so there are no placeholders. The architecture isolates MusicKit behind `MusicDiscoveryProviding`, keeping every untestable system-framework call in one file (`MusicKitDiscoveryProvider`) and everything with real logic (ID resolution, URI building, append flow, view state) unit-tested against `FakeMusicDiscoveryProvider`. The Sonos playback path is reused unchanged.

**Risks:**
- Library-playlist playback (Q1) may not work via a constructed URI → mitigated by the client-side track-expansion branch in Task 7.
- Library-only songs without a catalog id are unplayable on Sonos → surfaced as disabled rows, not errors.
- MusicKit symbol names may differ slightly on the local SDK → Task 5 Step 2 fixes at build time; mapper structure is stable.
