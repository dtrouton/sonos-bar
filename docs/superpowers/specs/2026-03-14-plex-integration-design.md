# SonoBar Plex Integration

## Overview

Direct integration with a local Plex Media Server for browsing and playing audiobooks and music on Sonos speakers. Bypasses Sonos's limited Plex support to provide library browsing, search, and bi-directional resume tracking — particularly for audiobooks.

## User Context

- Plex server at `192.168.68.78:32400` (static IP, NAS-hosted)
- Two audio libraries: **Audiobooks** (section 5, 359 titles) and **Music** (section 3, 894 albums)
- Primary use case: bedtime audiobooks for kids with resume ("continue Harry Potter in Connor's room")
- Secondary: music playback from personal library

## Architecture

Two layers, matching the existing SonoBar pattern:

### PlexClient (SonoBarKit)

HTTP client that talks to the Plex server's REST API. All requests are plain HTTP GET/PUT to `http://{ip}:32400/...` with `X-Plex-Token` header. Responses parsed as JSON (`Accept: application/json`).

No external dependencies. Same pattern as `SOAPClient` — a `Sendable` final class initialized with server IP and token.

### Plex Browse UI (SonoBar)

New views in the Browse tab for Plex content. Uses PlexClient for data, triggers playback by constructing Plex audio URLs and sending them to Sonos via `SetAVTransportURI` with minimal DIDL-Lite metadata (so Sonos displays track title and artist in Now Playing).

## PlexClient API

```
PlexClient
├── getLibraries() -> [PlexLibrary]
├── search(query:, sectionId:?) -> [PlexSearchResult]
├── getAlbums(sectionId:) -> [PlexAlbum]
├── getTracks(albumId:) -> [PlexTrack]
├── getOnDeck(sectionId:) -> [PlexTrack]
├── getRecentlyPlayed(sectionId:) -> [PlexAlbum]
├── reportProgress(trackId:, offsetMs:, duration:, state:)
├── thumbURL(path:) -> URL
└── audioURL(partKey:) -> URL
```

### Endpoint Mapping

| Method | Plex API Endpoint |
|--------|-------------------|
| `getLibraries` | `GET /library/sections` |
| `search` | `GET /hubs/search?query={q}&type=9,10` (type 9 = album, 10 = track) |
| `getAlbums` | `GET /library/sections/{id}/all?type=9` |
| `getTracks` | `GET /library/metadata/{albumId}/children` |
| `getOnDeck` | `GET /library/sections/{id}/onDeck` |
| `getRecentlyPlayed` | `GET /library/sections/{id}/recentlyViewed` |
| `reportProgress` | `PUT /:/timeline?ratingKey={id}&key=/library/metadata/{id}&state={state}&time={offsetMs}&duration={dur}` |
| `thumbURL` | `http://{ip}:32400{thumbPath}?X-Plex-Token={token}` |
| `audioURL` | `http://{ip}:32400{partKey}?X-Plex-Token={token}` |

Note: `thumbURL` and `audioURL` include the token as a query parameter because these URLs are consumed by Sonos speakers and SwiftUI image loaders, which cannot set custom headers. The token should not appear in user-visible logs.

### Models

```swift
struct PlexLibrary: Identifiable, Sendable {
    let id: String          // section key ("3", "5")
    let title: String       // "Music", "Audiobooks"
    let type: String        // "artist", "show", etc. — Plex section type
}

struct PlexAlbum: Identifiable, Sendable {
    let id: String          // ratingKey
    let title: String
    let artist: String      // parentTitle
    let thumbPath: String?
    let trackCount: Int     // leafCount
    let year: Int?
    let viewOffset: Int?    // aggregate progress for in-progress audiobooks (ms)
}

struct PlexTrack: Identifiable, Sendable {
    let id: String          // ratingKey
    let title: String
    let albumTitle: String  // parentTitle
    let artistName: String  // grandparentTitle
    let duration: Int       // milliseconds
    let viewOffset: Int     // milliseconds (0 = unplayed)
    let index: Int          // track number
    let partKey: String     // "/library/parts/{id}/{ts}/file.mp3"
    let thumbPath: String?
    let lastViewedAt: Date? // for sorting continue listening
}
```

## Browse UX

The Browse tab gains a segment picker: **Recents | Plex**

### Plex Tab Layout

```
┌─────────────────────────────┐
│ 🔍 Search audiobooks, music │
├─────────────────────────────┤
│ ▶ Continue Listening        │
│ ┌─────┐                     │
│ │cover│ Going Postal        │
│ │     │ 5% · 44m in         │
│ └─────┘                     │
│ ┌─────┐                     │
│ │cover│ Bunny vs Monkey     │
│ │     │ 19% · 30m in        │
│ └─────┘                     │
├─────────────────────────────┤
│ 📚 Audiobooks (359)     ▶   │
│ 🎵 Music (894 albums)   ▶   │
└─────────────────────────────┘
```

### Continue Listening

- Uses Plex's `/onDeck` endpoint per library (server-side filtering of in-progress items)
- Results merged across both libraries, sorted by `lastViewedAt` descending
- Each row: cover art, title, artist/author, progress bar, progress text
- Tap to resume on the active Sonos speaker (plays from saved offset)
- This is the primary interaction for the bedtime use case

### Library Browsing

Tap a library → album/audiobook grid (same `ContentGridView` layout with artwork):

- **Audiobooks**: sorted alphabetically, shows author and track count
- **Music**: sorted alphabetically by artist, shows year

Tap an album → track list with track numbers, titles, durations. Tap a track to play it. For audiobooks, tapping the album could offer "Play from beginning" vs "Resume" if there's a saved offset.

### Search

Search bar at the top of the Plex tab. Uses Plex's server-side search (`/hubs/search`). Results grouped:

- **Audiobooks** — matching titles and authors
- **Music** — matching artists, albums, tracks

Tap a result to navigate to the album/track, same as browsing.

### Error States

- **Server unreachable**: "Can't reach Plex server" with Retry button
- **Token invalid (401)**: "Plex token expired — update in settings" with Settings link
- **Empty library**: "No audiobooks found" / "No music found"
- **Search no results**: "No results for '{query}'"

## Playback

### Starting Playback

1. Clear the Sonos queue (`RemoveAllTracksFromQueue`)
2. For each track in the album/audiobook, construct the audio URL and a minimal DIDL-Lite metadata envelope:
   ```xml
   <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
              xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
     <item>
       <dc:title>{trackTitle}</dc:title>
       <dc:creator>{artistName}</dc:creator>
       <upnp:album>{albumTitle}</upnp:album>
       <upnp:class>object.item.audioItem.musicTrack</upnp:class>
     </item>
   </DIDL-Lite>
   ```
3. Add each track to queue via `AddURIToQueue` (AVTransport action) with the audio URL and DIDL metadata
4. Start playback from track 1 via `Seek` with `Unit=TRACK_NR, Target=1` then `Play`

This ensures next/previous controls work across all tracks in an album or audiobook.

### PlaybackController Additions

New methods needed in `PlaybackController`:

```swift
func clearQueue() async throws
func addToQueue(uri: String, metadata: String) async throws
```

These wrap the `RemoveAllTracksFromQueue` and `AddURIToQueue` AVTransport actions.

### Resume

When resuming an in-progress audiobook:

1. Read `viewOffset` from the PlexTrack (e.g., 2,640,000ms = 44 minutes)
2. Enqueue the album tracks into the Sonos queue (as above)
3. Seek to the correct track number, then `Play`
4. **Wait for `PLAYING` state** — poll `GetTransportInfo` every 250ms (up to 5 seconds) until the speaker reports `PLAYING`. Sonos rejects `Seek` calls during `TRANSITIONING` state while buffering.
5. Seek to the time offset via `AVTransport.Seek` with `REL_TIME` target

The wait-for-playing step is critical — without it, the time seek will silently fail and the audiobook starts from the beginning.

### Progress Reporting

Bi-directional sync — SonoBar reports playback position back to Plex so progress is consistent across all Plex clients.

**When to report:**
- When the user pauses playback (via SonoBar controls)
- When the user switches rooms
- When the user closes the popover while playing
- Periodically every 30 seconds during active playback

**How to report:**
```
PUT /:/timeline?ratingKey={trackId}&key=/library/metadata/{trackId}&state={playing|paused|stopped}&time={offsetMs}&duration={durationMs}&X-Plex-Token={token}
```

The `time` value comes from Sonos's `GetPositionInfo` → `RelTime` field, converted to milliseconds.

### Identifying Plex Playback

To know when to report progress, the app tracks whether the current session is Plex-sourced:

- **SonoBar-initiated**: When SonoBar starts Plex playback, store the active `PlexTrack.id` and `albumId` in AppState. Progress reporting is active.
- **Externally-initiated**: When the app detects a track URI containing the Plex server IP+port (e.g., `192.168.68.78:32400`), it can identify it as Plex content even if started by another app. Extract the `partKey` from the URI to look up the `ratingKey` for progress reporting.
- **On app restart**: The in-memory Plex session flag is lost. The app checks the current `TrackURI` against the Plex server address to re-identify Plex playback.

Progress is only reported when a Plex session is identified. The `sourceBadge` detection in NowPlayingView should also check for the Plex server IP in the track URI (since direct HTTP URLs don't contain the string "plex").

## Configuration

### First-Time Setup

1. **Primary**: mDNS/Bonjour discovery via `NWBrowser` for `_plex._tcp.local.` service (instant, privacy-respecting, uses the same Network.framework as SSDP)
2. **Fallback**: subnet scan of port 32400 with 300ms timeout (if mDNS doesn't find it)
3. If found, show a setup prompt: "Found Plex server at {ip}. Paste your Plex token to connect."
4. Link to instructions for finding the token (Plex Web UI → Get Info → View XML → copy token from URL)

### Storage

- **Server IP**: UserDefaults (key: `plexServerIP`)
- **Plex token**: macOS Keychain (service: `com.sonobar.plex`, account: `token`)
- PlexClient is initialized from these on app launch

### Settings UI

A small settings section (accessible from the Plex tab or a gear icon) to:
- Change server IP
- Update token
- Re-scan for servers
- Disconnect (clear IP + token)

## Album Art

Plex provides artwork via `thumb` attributes on albums and tracks. Construct the URL as:

```
http://{ip}:32400{thumbPath}?X-Plex-Token={token}
```

Use the same `GridArtworkView` pattern from the Recents grid — lazy loading with `.task(id:)`.

## New Files

| Layer | File | Purpose |
|-------|------|---------|
| SonoBarKit | `Models/PlexModels.swift` | PlexLibrary, PlexAlbum, PlexTrack structs |
| SonoBarKit | `Services/PlexClient.swift` | HTTP client for Plex API |
| SonoBar | `Services/PlexKeychain.swift` | Keychain read/write for token |
| SonoBar | `Views/PlexBrowseView.swift` | Main Plex tab with continue listening + libraries |
| SonoBar | `Views/PlexAlbumListView.swift` | Album/audiobook grid for a library |
| SonoBar | `Views/PlexTrackListView.swift` | Track list for an album |
| SonoBar | `Views/PlexSetupView.swift` | First-time setup / settings |

### Modified Files

- `AppState.swift` — PlexClient lifecycle, Plex playback tracking, progress reporting
- `BrowseView.swift` — add Plex segment to picker
- `ContentGridView.swift` — reuse for Plex album grids (already supports artwork)
- `PlaybackController.swift` — add `clearQueue()` and `addToQueue()` methods
- `NowPlayingView.swift` — update `sourceBadge` to detect Plex server IP in track URI

## Testing

### SonoBarKit Tests

- **PlexClientTests** — mock HTTP responses for each endpoint, verify URL construction, JSON parsing, token header inclusion
- **PlexModelsTests** — parse sample Plex JSON responses into model structs

### Manual Testing

- Browse audiobooks/music library
- Search across libraries
- Play a track on Sonos speaker
- Resume an in-progress audiobook (verify seek waits for PLAYING state)
- Verify progress reported back to Plex (check in Plex Web UI)
- Multi-track album: verify next/previous work
- First-time setup flow with auto-discovery
- Error states: server offline, invalid token, empty library

## Out of Scope

- Plex.tv cloud authentication (LAN-only, token pasted manually)
- Transcoding (Sonos plays the files directly — if format isn't supported, it won't play)
- Playlists in Plex (could be added later)
- Video libraries (Films, TV — not relevant for Sonos audio playback)
- Multiple Plex servers
