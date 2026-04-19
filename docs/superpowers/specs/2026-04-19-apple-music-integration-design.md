# SonoBar Apple Music Integration

## Overview

Add Apple Music catalog search + queue-append playback to SonoBar. Uses the public **iTunes Search API** for catalog discovery and **credentials extracted from the speaker's existing favorites/saved queues** for playback authorization. No MusicKit, no Apple Developer Program, no SMAPI access required.

This is *not* a full library browser. You cannot see "My Playlists" or "Liked Songs" — that data only exists behind SMAPI, which requires Sonos-signed device certs (TLS-gated; confirmed closed during Task 0 spike). Instead, SonoBar gives you: **"find and play anything on Apple Music from the menu bar without switching apps."**

## User Context

- SonoBar user has Apple Music linked on Sonos via the official app.
- User has favorited or saved-queued at least one Apple Music item in the Sonos app (hard prerequisite — this is how we harvest playback credentials).
- Primary use: catalog search (track/album/artist) → tap a result → appends to the current Sonos queue.
- V1 scope: search + queue-append for tracks, albums, and artists' top tracks. Detail views show track lists for albums.

## Research History (why this approach, not SMAPI or MusicKit)

The Task 0 spike surfaced concrete limits that reshape the design. Documented in full at [`docs/superpowers/notes/2026-04-19-apple-music-smapi-spike.md`](../notes/2026-04-19-apple-music-smapi-spike.md). Summary:

- **ContentDirectory.Browse on the speaker** only exposes local content (`A:`/`S:`/`SQ:`/`R:`/`FV:`/`Q:`). It does not proxy Apple Music library. Every service-prefixed ObjectID returned `701 UPnPError`.
- **MusicServices.Search is not a real SOAP action** on the speaker — the speaker's `MusicServices` service only supports `ListAvailableServices`, `UpdateAvailableServices`, `GetSessionId`. We saw `401 UPnPError` which is "no such action" (confirmed by also trying `GetSessionId` and getting a different `806` code for invalid argument).
- **Apple's SMAPI endpoint** (`https://sonos-music.apple.com/ws/SonosSoap`) is TLS-gated to Sonos-signed clients. Every call from our test harness — unauth'd, with AppLink credentials block, with householdId + deviceId, with proper `User-Agent: Linux UPnP/1.0 Sonos/86.6-75110 (ZPS37)` — returned the generic `SonosError 999`. Sonos' own docs confirm: *"Sonos locked down communication with most services, by no longer allowing access to the needed access tokens."* (svrooij/sonos-api docs).
- **scottwaters/SonosController** — a native macOS Sonos controller — explicitly takes this same approach: iTunes Search for catalog, credentials extracted from favorites for playback. Their README notes "one favorited song" as the only user prerequisite.
- **Playback test during spike** (via direct SOAP from this session):
  - Track URI (`x-sonos-http:song%3a1422700837.mp4?sid=204&flags=8224&sn=19`) with DIDL using extracted token (`SA_RINCON52231_X_#Svc52231-890cb54f-Token`) → `AddURIToQueue` succeeded, `NumTracksAdded=1`.
  - Album container URI (`x-rincon-cpcontainer:1004206calbum%3a1649042949`) → `AddURIToQueue` succeeded with `NumTracksAdded=9` (expanded server-side). Container URI needs no `sid`/`sn`/`flags` suffix, just the right DIDL.

This gives us a concrete, verified path. MusicKit remains the only route to user library data if that turns out to be needed — explicitly deferred.

## Architecture

```
SonoBarKit/
├── Models/
│   └── AppleMusicModels.swift             NEW: Track, Album, Artist, SearchResults, Error, Playable
└── Services/
    ├── ITunesSearchClient.swift           NEW: public iTunes Search API (no auth)
    ├── AppleMusicCredentials.swift        NEW: extract sn + token from FV:2 / SQ:
    └── AppleMusicURIs.swift               NEW: pure URI + DIDL helpers, parameterized by credentials

SonoBar/
├── Views/
│   ├── AppleMusicSearchView.swift         NEW: search + grouped results + album detail
│   └── AppleMusicAlbumDetailView.swift    NEW: track list for an album from iTunes lookup
├── Views/BrowseView.swift                 MODIFY: add .appleMusic segment
└── Services/AppState.swift                MODIFY: credentials discovery, append actions
```

No setup view, no keychain entry. If credential extraction fails (no Apple Music favorites or saved queues exist), the Apple Music tab shows an empty state: *"Favorite one Apple Music track in the Sonos app to enable playback here."*

## Known Playback Constants

Confirmed via the Task 0 spike on a live speaker:

- Service ID: `sid = 204`
- Service type: `52231` (= `204 * 256 + 7`)
- **DIDL `desc` token: discovered per-account from extracted favorites** — format is `SA_RINCON52231_X_#Svc52231-{ACCOUNT_TOKEN}-Token` where `ACCOUNT_TOKEN` is a per-account hex string (e.g. `890cb54f`). The node-sonos-http-api static template uses `-0-` which is **wrong for recent Apple Music accounts**.
- `sn`: discovered per-account from extracted favorites. For this user's account: `sn=19`. (Discovery via `MusicServices.ListAvailableServices` returns `sn=5` for the currently-linked account, but the working `sn` in saved favorites is `19` — we trust the favorite's `sn`, not the discovery one.)

| Item | URI | UPnP class |
|------|-----|-----------|
| Track | `x-sonos-http:song%3a{id}.mp4?sid=204&flags=8224&sn={sn}` | `object.item.audioItem.musicTrack` |
| Album | `x-rincon-cpcontainer:1004206calbum%3a{id}` | `object.container.album.musicAlbum` |
| Playlist | `x-rincon-cpcontainer:1006206cplaylist%3a{id}` | `object.container.playlistContainer` |

Playlist URIs are not reachable via V1 (no library browse) but the format is documented for future reference — iTunes Search API does not return playlists.

## iTunes Search API

Public HTTPS endpoint, no key, no rate limit of consequence for user-interactive use.

- Search: `https://itunes.apple.com/search?term={q}&media=music&entity={song|album|musicArtist}&limit={n}&country={cc}`
- Lookup album contents: `https://itunes.apple.com/lookup?id={collectionId}&entity=song`
- Lookup artist top songs: `https://itunes.apple.com/lookup?id={artistId}&entity=song&limit=25`

Returns JSON with (per result):
- `trackId`, `collectionId`, `artistId` — all compatible with Sonos `song:ID` / `album:ID` URIs (confirmed: a real iTunes `trackId` plugged into our URI template played successfully).
- `trackName`, `collectionName`, `artistName`
- `artworkUrl100` (can be upsized to 600x600 by string replacement)
- `trackTimeMillis` for duration

`country` code defaults to the storefront the account is in — derived from the favorite's marketplace where possible, else `US` as fallback. For this user, storefront appears to be `GB` (the account is `audible.co.uk` per `SonosAudibleParams`).

## Credential Extraction

Parse the speaker's ContentDirectory responses for `FV:2` (Favorites) and `SQ:` (Saved Queues). Any entry with `sid=204` in a `res` URI or `albumArtURI` yields:

- `sn`: extracted from URI query string (`?sid=204&sn=19&flags=...`)
- `accountToken`: extracted from the embedded DIDL `<desc>` element inside `<r:resMD>` for `FV:2` entries (encoded HTML entities — decode first). For `SQ:` entries, only `sn` is available; token must come from a favorite.

Precedence:
1. Walk `FV:2` first — each favorite has both `sn` (in `res` URI) and the account token (in nested `<r:resMD>`'s `<desc>`).
2. Fall back to `SQ:` for `sn` only if no Apple Music favorites exist.
3. Cache in `UserDefaults` once extracted (parallel to the existing `SonosAudibleParams`). Re-extract if cached credentials fail a playback.

Failure mode: if no favorites and no saved queues have `sid=204`, surface the "favorite one track" empty state.

## Models

```swift
public struct AppleMusicTrack: Sendable, Identifiable, Equatable {
    public let id: String           // trackId from iTunes, used in song:ID URIs
    public let title: String
    public let artist: String?
    public let album: String?
    public let albumId: String?     // collectionId — for album detail linking
    public let artworkURL: URL?
    public let durationSec: Int?
}

public struct AppleMusicAlbum: Sendable, Identifiable, Equatable {
    public let id: String           // collectionId, used in album:ID URIs
    public let title: String
    public let artist: String?
    public let artworkURL: URL?
    public let trackCount: Int?
}

public struct AppleMusicArtist: Sendable, Identifiable, Equatable {
    public let id: String           // artistId — for top-songs lookup
    public let name: String
}

public struct AppleMusicSearchResults: Sendable, Equatable {
    public let tracks: [AppleMusicTrack]
    public let albums: [AppleMusicAlbum]
    public let artists: [AppleMusicArtist]
}

public enum AppleMusicPlayable: Sendable, Equatable {
    case track(AppleMusicTrack)
    case album(AppleMusicAlbum)
}

public struct AppleMusicCredentials: Sendable, Equatable {
    public let sn: Int              // e.g. 19
    public let accountToken: String // e.g. "890cb54f"
}

public enum AppleMusicError: Error, Sendable, Equatable {
    case notLinked                  // no sid=204 credentials found on speaker
    case networkError
    case httpError(Int)
    case invalidResponse
}
```

## `ITunesSearchClient` API

```swift
public final class ITunesSearchClient: Sendable {
    public init(country: String = "US",
                httpClient: HTTPClientProtocol = URLSessionHTTPClient())

    public func search(_ term: String) async throws -> AppleMusicSearchResults
    public func albumTracks(albumId: String) async throws -> [AppleMusicTrack]
    public func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack]
}
```

Implementation notes:
- One search call hits the iTunes endpoint three times (once per entity type) and merges results. iTunes doesn't support a single multi-entity query, and parallel `async let` keeps latency bounded.
- JSON decoded via `Codable`.
- `artworkUrl100` → `artworkUrl600` via string replace of `100x100bb.jpg` → `600x600bb.jpg`.

## `AppleMusicCredentials` extraction

Pure parsing logic, unit-testable with captured DIDL fixtures (spike output provides the exact shapes). Discovery from `AppState`:

```swift
extension AppState {
    func discoverAppleMusicCredentials() async -> AppleMusicCredentials?
}
```

1. Load cached credentials from `UserDefaults`.
2. If none, call `ContentBrowser.browseFavorites(client:)` and walk DIDL for the first `sid=204` entry. Extract `sn` from the `res` URI, extract `accountToken` from the embedded `<r:resMD>`'s `<desc>` element.
3. If still none, call `ContentBrowser.browsePlaylists(client:)` for `SQ:` entries (provides `sn` only — prompts user to favorite to get token).
4. Cache successful extraction. Return.

## `AppleMusicURIs`

Pure functions (stateless):

```swift
public enum AppleMusicURIs {
    public static func trackURI(id: String, sn: Int) -> String
    public static func albumContainerURI(id: String) -> String
    public static func didl(for item: AppleMusicPlayable,
                            credentials: AppleMusicCredentials) -> String
}
```

DIDL template uses `credentials.accountToken` for the `desc` value, not the hardcoded `-0-`.

## Data Flow

### App start
1. `AppState` startup calls `discoverAppleMusicCredentials()` after device discovery settles.
2. Credentials cached on `AppState` — nil means "not extractable yet" (show empty state in Apple Music tab).

### Search
1. User opens Apple Music tab → search-centric view appears (no library, no landing sections).
2. Debounce 300ms on search field.
3. `ITunesSearchClient.search(term)` — results split into Tracks / Albums / Artists sections.
4. Tap track → append + confirmation.
5. Tap album → push album detail view (fetches tracks via `ITunesSearchClient.albumTracks(albumId:)`).
6. Tap artist → push a "Top tracks by {artist}" list (via `artistTopTracks(artistId:)`) — treat it like an implicit playlist.

### Playback (queue-append)
1. Resolve an `AppleMusicPlayable` from UI interaction.
2. Build URI + DIDL using `AppleMusicURIs` with stored credentials.
3. Call `PlaybackController.addToQueue(uri:metadata:)`.
4. Success: silent for V1. On first-ever success, optionally log to recents.

### Failure paths
- No credentials → empty state with clear copy: "Favorite one Apple Music track in the Sonos app to enable playback."
- iTunes Search error → inline retry in the search view.
- Playback SOAP error → single error surface in `AppState` (reuse Audible/Plex pattern).
- If the speaker returns an error during `AddURIToQueue` (e.g. credentials invalidated), invalidate cached credentials and prompt re-discovery on next attempt.

## Testing

- **Unit tests: `AppleMusicURIs`** — every URI + DIDL shape asserted against expected strings, including account-token substitution.
- **Unit tests: `AppleMusicCredentials`** — fixture-based parsing of real `FV:2` and `SQ:` DIDL captured in the spike; covers: Apple Music favorite present, only Sonos Radio favorites present, only saved queues present, nothing present.
- **Unit tests: `ITunesSearchClient`** — mocked `HTTPClientProtocol` + JSON fixtures; covers: multi-entity search result merging, album lookup, artist top-tracks, network error mapping, malformed JSON → `.invalidResponse`.
- **No E2E tests against live speaker or iTunes** — matches existing `AudibleClient`/`PlexClient` policy. Manual QA on a real Sonos covers integration.
- **No view tests** — matches existing practice.

## Non-goals (explicit)

- **User library browsing** (playlists, saved albums, liked songs) — unreachable without MusicKit. Deferred. If it becomes essential, revisit with a fresh design that pays for the Developer Program.
- **Radio stations** (`x-sonosapi-radio:` URIs) — deferred.
- **"For You" / editorial recommendations** — iTunes Search doesn't expose these.
- **Recently played** — no user-specific data surface.
- **Library-scoped search** — only catalog search exists.
- **Share-URL paste** — iTunes Search covers the same need more fluidly. Not needed for V1.
- **Credentials setup flow** — no UI; user must favorite a track in the Sonos app. We surface the requirement, not a flow to satisfy it.

## Open Questions

(All resolvable during implementation; none block accepting this spec.)

- **Storefront code** (`country=GB` vs `US`): best inferred from `AppState.sonosAudibleParams.marketplace` (we already discover `co.uk`) — fall through to `US` if unavailable. Implementation decides at `ITunesSearchClient` init time.
- **What if the user's active account has a different `accountToken` than the favorite's**? The Task 0 spike showed `sn=5` from discovery vs `sn=19` from favorites. We trust favorites. Tests should cover the case of multiple accounts linked and picking the most recent Apple Music favorite.
- **Artwork upsizing**: the `100x100bb.jpg` → `600x600bb.jpg` rewrite works for most results but iTunes occasionally returns different URL shapes. Fall back to the original URL if the rewrite would produce an invalid URL.

## References

- [Task 0 spike findings](../notes/2026-04-19-apple-music-smapi-spike.md) — the empirical basis for this design
- [scottwaters/SonosController](https://github.com/scottwaters/SonosController) — the reference implementation for this approach
- [svrooij Sonos API docs — music services](https://sonos.svrooij.io/music-services) — confirms SMAPI lockdown
- [jishi/node-sonos-http-api appleDef.js](https://github.com/jishi/node-sonos-http-api/blob/master/lib/music_services/appleDef.js) — URI templates (but `-0-` token is stale)
- [Apple iTunes Search API](https://performance-partners.apple.com/search-api) — the catalog-search surface this design relies on
