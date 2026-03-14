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

New views in the Browse tab for Plex content. Uses PlexClient for data, triggers playback by constructing Plex audio URLs and sending them to Sonos via `SetAVTransportURI`.

## PlexClient API

```
PlexClient
├── getLibraries() -> [PlexLibrary]
├── search(query:, sectionId:?) -> [PlexSearchResult]
├── getAlbums(sectionId:) -> [PlexAlbum]
├── getTracks(albumId:) -> [PlexTrack]
├── getInProgress(sectionId:) -> [PlexTrack]
├── getRecentlyPlayed(sectionId:) -> [PlexAlbum]
├── reportProgress(trackId:, offsetMs:, duration:)
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
| `getInProgress` | `GET /library/sections/{id}/all?type=10&sort=lastViewedAt:desc` (filter `viewOffset > 0` client-side) |
| `getRecentlyPlayed` | `GET /library/sections/{id}/recentlyViewed` |
| `reportProgress` | `PUT /:/timeline?ratingKey={id}&key=/library/metadata/{id}&state=stopped&time={offsetMs}&duration={dur}` |
| `thumbURL` | `http://{ip}:32400{thumbPath}?X-Plex-Token={token}` |
| `audioURL` | `http://{ip}:32400{partKey}?X-Plex-Token={token}` |

### Models

```swift
struct PlexLibrary: Identifiable, Sendable {
    let id: String          // section key ("3", "5")
    let title: String       // "Music", "Audiobooks"
    let type: String        // "artist"
}

struct PlexAlbum: Identifiable, Sendable {
    let id: String          // ratingKey
    let title: String
    let artist: String      // parentTitle
    let thumbPath: String?
    let trackCount: Int     // leafCount
    let year: Int?
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

- Shows tracks with `viewOffset > 0` across both libraries, sorted by `lastViewedAt` descending
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

## Playback

### Starting Playback

1. Construct the audio URL: `http://192.168.68.78:32400/library/parts/{partId}/{timestamp}/file.mp3?X-Plex-Token={token}`
2. Call Sonos `SetAVTransportURI` with this URL and empty metadata
3. Call `Play`

For albums/audiobooks with multiple tracks: enqueue all tracks into the Sonos queue so next/previous controls work. Use `AddURIToQueue` for tracks 2+, then start playback of the first track.

### Resume

When resuming an in-progress audiobook:

1. Read `viewOffset` from the PlexTrack (e.g., 2,640,000ms = 44 minutes)
2. Start playback on Sonos (SetAVTransportURI + Play)
3. Seek to the offset position via `AVTransport.Seek` with `REL_TIME` target

### Progress Reporting

Bi-directional sync — SonoBar reports playback position back to Plex so progress is consistent across all Plex clients.

**When to report:**
- When the user pauses playback (via SonoBar controls)
- When the user switches rooms
- When the user closes the popover while playing
- Periodically every 30 seconds during playback (piggyback on the existing 1s refresh timer, but only report every 30s)

**How to report:**
```
PUT /:/timeline?ratingKey={trackId}&key=/library/metadata/{trackId}&state={playing|paused|stopped}&time={offsetMs}&duration={durationMs}&X-Plex-Token={token}
```

The `time` value comes from Sonos's `GetPositionInfo` → `RelTime` field, converted to milliseconds.

### Identifying Plex Playback

To know when to report progress, the app needs to know the current playback is Plex-sourced. Store the active `PlexTrack.id` (ratingKey) when playback starts. Clear it when the source changes to non-Plex content. The existing `refreshPlayback()` timer can check this flag.

## Configuration

### First-Time Setup

1. Auto-scan: hit `http://{subnet}.{1-254}:32400/identity` with 300ms timeout (same approach that successfully found the server during brainstorming)
2. If found, show a setup prompt: "Found Plex server at {ip}. Paste your Plex token to connect."
3. Link to instructions for finding the token (Plex Web UI → Get Info → View XML → copy token from URL)

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

## Testing

### SonoBarKit Tests

- **PlexClientTests** — mock HTTP responses for each endpoint, verify URL construction, JSON parsing, token header inclusion
- **PlexModelsTests** — parse sample Plex JSON responses into model structs

### Manual Testing

- Browse audiobooks/music library
- Search across libraries
- Play a track on Sonos speaker
- Resume an in-progress audiobook
- Verify progress reported back to Plex (check in Plex Web UI)
- Multi-track album: verify next/previous work
- First-time setup flow with auto-discovery

## Out of Scope

- Plex.tv cloud authentication (LAN-only, token pasted manually)
- Transcoding (Sonos plays the files directly — if format isn't supported, it won't play)
- Playlists in Plex (could be added later)
- Video libraries (Films, TV — not relevant for Sonos audio playback)
- Multiple Plex servers
