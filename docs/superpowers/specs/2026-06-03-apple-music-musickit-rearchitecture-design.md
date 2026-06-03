# SonoBar Apple Music — MusicKit Re-architecture

## Overview

Replace the iTunes Search discovery layer with **MusicKit** (the user is enrolling in the
Apple Developer Program, which unlocks it). This gains catalog search backed by the user's
own account, plus the two surfaces the iTunes approach structurally could not provide:
**My Playlists** and **My Library (albums/songs)**.

The entire **playback-to-Sonos path stays unchanged** — `AppleMusicURIs`,
`AppleMusicCredentialsExtractor`, `AppleMusicKeychain`, `AppState.discoverAppleMusicCredentials()`,
`appendAppleMusic*`, and the auto-play logic are proven on a live speaker and MusicKit does not
touch them.

### The core fact that shapes this design

**MusicKit cannot drive a Sonos speaker.** MusicKit's players (`ApplicationMusicPlayer` /
`SystemMusicPlayer`) only play on the local Mac or hand off to the system Music app. Sonos plays
Apple Music through its own internal SMAPI link, authorized by a per-account Sonos-side token that
MusicKit knows nothing about. So the integration has two **orthogonal** halves:

| Half | Today | This re-architecture |
|------|-------|----------------------|
| **Discovery** — search, library, playlists | iTunes Search API | **MusicKit** (the change) |
| **Playback to Sonos** — URI + DIDL + `AddURIToQueue` with account token | extracted from a favorite | **unchanged** |

"Replace with MusicKit" therefore means: replace the discovery engine; keep the playback plumbing.
The credential-extraction prerequisite (favorite one Apple Music item in the Sonos app) **remains**,
because that token is Sonos-side authorization, independent of Apple's.

## Decisions (from brainstorming)

- **Playback path:** keep credential extraction + URI/DIDL. MusicKit for discovery only.
- **Discovery scope:** catalog search, My Playlists, Library albums/songs. **Deferred:**
  Recently Played / For You.
- **Browse-but-no-play UX:** keep today's gate — nothing shows until a Sonos token exists, then
  reveal browsing. MusicKit authorization layers on top of that gate.
- **Structure:** Approach A — protocol boundary isolating MusicKit behind a seam.

## Architecture (Approach A — protocol boundary)

```
SonoBarKit/  (Swift package — unit-tested)
├── Models/AppleMusicModels.swift           MODIFY: + AppleMusicPlaylist; + .playlist case (conditional on spike)
├── Services/
│   ├── MusicDiscoveryProviding.swift         NEW: the protocol (the seam) + MusicAuthStatus enum
│   ├── MusicKitDiscoveryProvider.swift        NEW: the ONLY MusicKit-importing type; not unit-tested
│   ├── AppleMusicCatalogIDResolver.swift      NEW: pure mapper, library playParameters → catalog ID
│   ├── AppleMusicURIs.swift                   MODIFY: + playlist URI/DIDL (shape decided by spike)
│   ├── AppleMusicCredentialsExtractor.swift   UNCHANGED
│   └── ITunesSearchClient.swift               DELETE
└── Tests/
    ├── FakeMusicDiscoveryProvider             NEW: scriptable provider for AppState/view tests
    ├── AppleMusicCatalogIDResolverTests       NEW
    ├── AppleMusicURIsTests                    MODIFY (if spike Q1 succeeds)
    └── ITunesSearchClientTests                DELETE

SonoBar/  (app target — entitlements live here)
├── Services/AppState.swift                  MODIFY: swap itunesSearchClient → musicDiscovery; auth gating
├── Views/AppleMusicSearchView.swift         MODIFY: + Library/Playlists sections + auth states
├── Views/AppleMusicAlbumDetailView.swift    UNCHANGED (already takes albumId)
├── Views/AppleMusicPlaylistDetailView.swift NEW
├── Services/AppleMusicKeychain.swift        UNCHANGED
├── Info.plist                               MODIFY: + NSAppleMusicUsageDescription
└── SonoBar.entitlements                     MODIFY: + MusicKit capability
```

`MusicKitDiscoveryProvider` is deliberately the **single file in the codebase that imports
MusicKit**. Everything else depends on the protocol and the project's own value types, keeping the
blast radius of an untestable system framework to one file.

### Entitlement prerequisites (Developer Program work)

- Enable the **MusicKit** App Service for the bundle ID in the Apple Developer portal.
- Add `NSAppleMusicUsageDescription` to `Info.plist`.
- Add the MusicKit capability to the entitlements / provisioning profile.
- MusicKit-for-Swift handles developer/user tokens automatically once the app is signed with a
  MusicKit-enabled profile — no JWT generation (unlike MusicKit JS).
- Cannot be exercised in the Simulator; requires a real Mac with a signed-in Apple Music account.

## Components

### The seam — `MusicDiscoveryProviding`

```swift
public enum MusicAuthStatus: Sendable { case notDetermined, denied, authorized }

public protocol MusicDiscoveryProviding: Sendable {
    func currentAuthStatus() -> MusicAuthStatus
    func requestAuthorization() async -> MusicAuthStatus
    func search(_ term: String) async throws -> AppleMusicSearchResults
    func libraryPlaylists() async throws -> [AppleMusicPlaylist]
    func libraryAlbums() async throws -> [AppleMusicAlbum]
    func librarySongs() async throws -> [AppleMusicTrack]
    func playlistTracks(_ playlistId: String) async throws -> [AppleMusicTrack]
    func albumTracks(albumId: String) async throws -> [AppleMusicTrack]
}
```

Returns the existing `AppleMusic*` value types — views never see a MusicKit type. Errors map to the
existing `AppleMusicError` (`networkError`, `invalidResponse`, `httpError`, `notLinked`).

### New model — `AppleMusicPlaylist`

```swift
public struct AppleMusicPlaylist: Sendable, Identifiable, Equatable {
    public let id: String          // catalog "pl.xxx" or library "p.xxx"
    public let name: String
    public let curatorName: String?
    public let artworkURL: URL?
    public let trackCount: Int?
    public let isLibrary: Bool      // selects the URI form at playback time
}
```

`isLibrary` is carried explicitly so the URI builder stays a pure function of explicit inputs rather
than sniffing the ID prefix internally.

### ID resolution — `AppleMusicCatalogIDResolver`

Only catalog IDs are directly Sonos-playable. MusicKit produces three shapes:

- **Catalog song** → `Song.id.rawValue` *is* the numeric store ID → reuse the proven `trackURI`. ✅
- **Library song** → `id` is `l.xxx`; `song.playParameters` carries the catalog ID → resolve, then
  `trackURI`. A library-only/uploaded song with no catalog ID is **not Sonos-playable**. ⚠️
- **Library playlist** → `p.xxx`; playback shape decided by the spike (below).

The resolver is pure logic over `playParameters`-shaped input, so it is unit-testable without a live
MusicKit account.

## Data Flow

1. **Gate (unchanged):** no Keychain token → existing "Favorite one Apple Music track in the Sonos
   app" empty state. This remains the first gate.
2. **Authorize:** token exists → `AppState` calls `requestAuthorization()`. Denied → "Allow Apple
   Music access in System Settings." Authorized → proceed.
3. **Browse:** the Apple Music tab gains sections — **Search** (debounced, as today), **Playlists**,
   **Library**. Tapping a playlist or album pushes a detail view listing tracks.
4. **Play (unchanged path):** every playable resolves to a catalog `song:ID` or `album:ID`, then
   `AppState.appendAppleMusic*` builds URI + DIDL with the Keychain token and calls `addToQueue` —
   the exact verified path. A library song that won't resolve to a catalog ID is shown disabled.

## Task 0 — Spike (REQUIRED before building)

Resolve two Sonos-side unknowns via direct SOAP against a live speaker (same harness as the
2026-04-19 spike). Library-playlist playback was **never verified**; only catalog track and catalog
album were.

- **Q1:** Can a constructed **library-playlist** URI
  (`x-rincon-cpcontainer:...libraryplaylist%3a{p.id}...` with the account token) succeed at
  `AddURIToQueue` for a playlist the user has **not** favorited?
- **Q2:** Does a **library song's** `playParameters` reliably yield a catalog ID that plays via the
  existing `trackURI`?

### Spike outcomes drive scope

- **Q1 succeeds** → add `.playlist` to `AppleMusicPlayable` + `playlistContainerURI`; "Add playlist
  to queue" is one server-side call (Sonos expands the container).
- **Q1 fails** → "My Playlists" still ships, but "play playlist" **expands client-side**: fetch
  `playlistTracks`, append each as a catalog track. Reliable, just chattier; cap/log very large
  playlists.
- **Q2 succeeds** → library songs/albums fully playable.
- **Q2 fails for some items** → those rows disabled with an explanatory tooltip.

Either Q1 outcome ships a working "My Playlists" — only the mechanism changes.

## Error Handling

Extends the existing `AppState.appleMusicError` single-surface pattern.

| Failure | Behavior |
|---------|----------|
| MusicKit auth denied | "Allow Apple Music access in System Settings to browse your library." (no retry button — it's a Settings action) |
| MusicKit request throws | Inline "Couldn't load. Retry." in that section; mapped to `AppleMusicError` |
| Library song has no catalog ID | Row disabled (dimmed), not an error — an expected, explainable state |
| `addToQueue` rejected (stale token) | **Unchanged:** `clearAppleMusicCredentials()` + "Favorite a track in the Sonos app to refresh credentials" |
| No Apple Music subscription | Authorized but empty/play fails → stale-token-style message; refine copy in QA |

Auth and playback are **independent failure surfaces** with **different recovery actions** (open
System Settings vs. favorite a track in Sonos). A denied MusicKit permission never wipes the Sonos
token; a bad token never re-triggers the MusicKit prompt.

## Testing

Mirrors the shipped policy: unit-test pure/injectable parts, manual-QA the system edges.

- **`FakeMusicDiscoveryProvider`** (test target): scriptable returns + error injection. All
  `AppState` discovery/append logic and view-model behavior tests against the fake.
- **`AppleMusicCatalogIDResolver`** — unit-tested with fixture inputs (catalog song, library song
  with catalog ID, library-only song without).
- **`AppleMusicURIs`** — extend tests for the new playlist URI/DIDL shape (only if spike Q1 succeeds).
- **`MusicKitDiscoveryProvider`** — **no unit tests** (cannot instantiate MusicKit requests without a
  live account/entitlement); covered by manual QA, exactly as `ITunesSearchClient`'s live calls were.
- **Delete** `ITunesSearchClientTests`.
- **Manual QA on real hardware:** authorize flow, deny flow, search, open a playlist and play it
  (both spike outcomes), play a library album, a disabled library-only song, stale-token recovery,
  restart-loads-from-Keychain.

## Non-goals (explicit)

- **Recently Played / For You** — deferred.
- **Radio stations** (`x-sonosapi-radio:`) — deferred.
- **Playing on the Mac via MusicKit players** — out of scope; Sonos is the only output.
- **Removing the favorite-a-track prerequisite** — impossible without Sonos-side auth; it stays.
- **AirPlay-from-Mac path** — considered and rejected (changes the playback model; Mac must stay awake).

## Open Questions

(All resolvable during implementation; none block accepting this spec.)

- Exact library-playlist URI/DIDL shape — resolved by Task 0 Q1.
- Whether `MusicKitDiscoveryProvider` lives in `SonoBarKit` (imports MusicKit in the package) or the
  app target — default to `SonoBarKit` for cohesion with the other services; revisit if the package
  can't link MusicKit cleanly for the macOS 14 target.
- Library refresh cadence — fetch on tab open vs. cache; default to fetch-on-open for V1.

## References

- [2026-04-19 SMAPI spike findings](../notes/2026-04-19-apple-music-smapi-spike.md) — verified
  playback constants (sn, account token, catalog track/album URIs) reused unchanged here.
- [2026-04-19 iTunes integration design](2026-04-19-apple-music-integration-design.md) — the shipped
  approach this re-architecture replaces on the discovery side.
- [Apple MusicKit for Swift](https://developer.apple.com/documentation/musickit) — discovery surface.
