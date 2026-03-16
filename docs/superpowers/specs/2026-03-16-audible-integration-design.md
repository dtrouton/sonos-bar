# SonoBar Audible Integration

## Overview

Browse and play Audible audiobooks on Sonos speakers. Uses the Audible API (reverse-engineered, via mkb79/Audible documentation) for library browsing, chapter info, and resume positions. Playback goes through Sonos's built-in Audible service integration — SonoBar constructs the right URI and DIDL metadata, Sonos handles DRM and streaming.

## User Context

- Audible linked to Sonos (confirmed: `sid=239`, `sn=6` on speakers)
- Amazon marketplace: `co.uk`
- Primary use: bedtime audiobooks for kids with chapter navigation and resume
- Audible content already captured in recents from room scanning

## Architecture

Three components:

### AudibleClient (SonoBarKit)

HTTP client for the Audible REST API. Handles library browsing, chapter info, resume positions, and cover art URLs. Uses OAuth PKCE tokens stored in Keychain.

Base URL: `https://api.audible.co.uk` (marketplace-specific)

### SonosAudibleParams

Discovers Audible-specific Sonos service parameters by scanning speaker URIs. Stores `sid`, `sn`, marketplace suffix, and `desc` token in UserDefaults. These are needed to construct playback URIs from ASINs.

Discovery sources (in priority order):
1. Room scan — extract from any `x-rincon-cpcontainer:...?sid=239` URI and its DIDL `desc` element
2. MusicServices SOAP query — lists all linked services with account info (fallback)

### Audible Browse UI (SonoBar)

New segment in Browse tab: **Recents | Plex | Audible**

## AudibleClient API

```
AudibleClient
├── getLibrary() -> [AudibleBook]
├── getBook(asin:) -> AudibleBook
├── getChapters(asin:) -> [AudibleChapter]
├── getListeningPositions(asins:) -> [String: Int]
├── coverURL(imagePath:) -> URL
└── refreshTokensIfNeeded()
```

### Endpoint Mapping

| Method | Audible API Endpoint |
|--------|---------------------|
| `getLibrary` | `GET /1.0/library?num_results=500&response_groups=product_attrs,media,product_desc&sort_by=-PurchaseDate` |
| `getBook` | `GET /1.0/library/{asin}?response_groups=product_attrs,media,chapter_info` |
| `getChapters` | `GET /1.0/library/{asin}?response_groups=chapter_info` |
| `getListeningPositions` | `GET /1.0/annotations/lastpositions?asins={asin1,asin2,...}` |
| `coverURL` | Direct Amazon CDN URL from library response `product_images` field |
| `refreshTokensIfNeeded` | `POST /auth/token` with refresh token |

All requests include `Authorization: Bearer {access_token}` header.

### Models

```swift
struct AudibleBook: Identifiable, Sendable, Codable {
    let asin: String              // Amazon Standard ID
    let title: String
    let author: String            // from authors[0].name
    let narrator: String?         // from narrators[0].name
    let coverURL: String?         // from product_images
    let durationMs: Int           // runtime_length_ms
    let purchaseDate: Date?
    var id: String { asin }
}

struct AudibleChapter: Identifiable, Sendable, Codable {
    let title: String
    let startOffsetMs: Int
    let durationMs: Int
    var id: String { "\(startOffsetMs)" }
}

struct AudibleListeningPosition: Sendable {
    let asin: String
    let positionMs: Int
}
```

## Authentication

Amazon OAuth with PKCE, using a local HTTP server to capture the redirect.

### Flow

1. Generate `code_verifier` (random 32 bytes, base64url-encoded) and `code_challenge` (SHA256 of verifier, base64url-encoded)
2. Start `NWListener` on a random localhost port for the callback
3. Open browser to Amazon authorization URL:
   ```
   https://www.amazon.co.uk/ap/signin?
     client_id={audible_client_id}
     &response_type=code
     &code_challenge={challenge}
     &code_challenge_method=S256
     &redirect_uri=http://localhost:{port}/callback
   ```
4. User logs in with Amazon credentials (browser handles 2FA/CAPTCHA naturally)
5. Amazon redirects to `http://localhost:{port}/callback?code={auth_code}`
6. Local server captures the code, stops listening
7. Exchange code for tokens:
   ```
   POST https://api.amazon.co.uk/auth/o2/token
     grant_type=authorization_code
     &code={auth_code}
     &code_verifier={verifier}
     &redirect_uri=http://localhost:{port}/callback
     &client_id={audible_client_id}
   ```
8. Receive `access_token` (short-lived) and `refresh_token` (long-lived)
9. Store both in Keychain

### Token Refresh

Access tokens expire after ~1 hour. Before each API call, check expiry. If expired:
```
POST https://api.amazon.co.uk/auth/o2/token
  grant_type=refresh_token
  &refresh_token={refresh_token}
  &client_id={audible_client_id}
```

### Client ID and Device Registration

The Audible API requires a registered device. The mkb79/Audible library documents the client IDs and registration flow. Key values for UK marketplace:
- OAuth client ID: from Audible app reverse engineering (documented in mkb79/Audible)
- Device type: `A2CZJZGLK2JJVM` (Audible iOS app device type)
- Domain: `amazon.co.uk`

These are constants baked into the app.

## Sonos Service Parameters

### Discovery

On each `refreshAllRooms`, scan `roomStates` for Audible URIs:

```swift
// When mediaURI contains "sid=239"
// Extract: sn from query string, marketplace from URI suffix (_co.uk)
// Extract: desc from DIDL metadata
```

Store in UserDefaults:
- `audibleSonosSID` = `239`
- `audibleSonosSN` = `6`
- `audibleSonosDesc` = `SA_RINCON61191_X_#Svc61191-0-Token`
- `audibleMarketplace` = `co.uk`

### Fallback: MusicServices Query

If no speaker has Audible content loaded, query the Sonos `MusicServices` SOAP service to get the account serial number for Audible.

### URI Construction

For any ASIN:
```
URI: x-rincon-cpcontainer:00130000reftitle%3a{ASIN}_{marketplace}?sid={sid}&flags=0&sn={sn}
```

DIDL metadata:
```xml
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
           xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"
           xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
  <item id="00130000reftitle%3a{ASIN}_{marketplace}"
        parentID="-1" restricted="true">
    <dc:title>{book title}</dc:title>
    <upnp:class>object.item.audioItem.audioBook</upnp:class>
    <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">
      {desc token}
    </desc>
    <upnp:albumArtURI>{cover URL}</upnp:albumArtURI>
  </item>
</DIDL-Lite>
```

## Browse UX

Browse tab: **Recents | Plex | Audible**

### Audible Tab Layout

```
┌──────────────────────────────┐
│ 🔍 Search audiobooks         │
├──────────────────────────────┤
│ ▶ Continue Listening         │
│ ┌─────┐                      │
│ │cover│ Going Postal          │
│ │     │ 42% · 3h 20m left    │
│ └─────┘                      │
│ ┌─────┐                      │
│ │cover│ Unbelievable Truth S6 │
│ │     │ 65% · 10m left       │
│ └─────┘                      │
├──────────────────────────────┤
│ Library (sorted by recent)   │
│ ┌───┐ ┌───┐ ┌───┐           │
│ │   │ │   │ │   │           │
│ └───┘ └───┘ └───┘           │
│ Title  Title  Title          │
└──────────────────────────────┘
```

### Continue Listening

- Fetch library, then batch-fetch listening positions via `getListeningPositions`
- Show books with position > 0, sorted by most recently listened
- Each row: cover art, title, author, progress %, time remaining
- Tap to resume on active Sonos speaker

### Library

- Grid layout (same 3-column pattern as Plex)
- Sorted by purchase date (newest first)
- Cover art, title, author
- Search bar: client-side filtering by title/author

### Chapter List (on book tap)

Tap a book → chapter list view:

```
┌──────────────────────────────┐
│ ← Back                       │
│                              │
│ ┌────────┐ Going Postal      │
│ │ cover  │ Terry Pratchett    │
│ │        │ 13h 36m            │
│ └────────┘                    │
│                              │
│ [▶ Resume 42%] [▶ Play All] │
│                              │
│  1  Chapter 1        0:32:00 │
│  2  Chapter 2        0:28:00 │
│  3  Chapter 3    ▶   0:31:00 │
│     ████░░░░ 65%             │
│  4  Chapter 4        0:29:00 │
│  ...                         │
└──────────────────────────────┘
```

- Resume button: plays from saved position (seek to offset)
- Play All: starts from chapter 1
- Tap chapter: plays from that chapter's start offset
- Progress bar on the currently-in-progress chapter

### Error States

- **Not connected**: Show setup view (Sign in with Amazon)
- **Sonos params not found**: "Audible not linked to Sonos — open the Sonos app and add Audible as a service"
- **Token expired**: Auto-refresh; if refresh fails, prompt re-login
- **Library empty**: "No audiobooks found"
- **Server error**: "Can't reach Audible — check your internet connection"

## Playback

### Starting a Book

1. Construct URI and DIDL from ASIN + Sonos service params
2. Call `SetAVTransportURI` with the URI and DIDL metadata
3. Call `Play`

Sonos handles enqueuing chapters and DRM internally. The `x-rincon-cpcontainer:` URI tells Sonos to load the entire book.

### Resume / Chapter Jump

1. Start playback as above
2. Wait for `PLAYING` state (same `waitForPlaying` pattern as Plex)
3. Seek to the target offset via `AVTransport.Seek` with `REL_TIME`

For resume: offset from `getListeningPositions` API.
For chapter jump: offset from `getChapters` API (`startOffsetMs`).

### Progress Reporting

Not needed via Audible API — Sonos reports progress to Audible directly through its built-in service integration. The Audible app and API will reflect updated positions automatically.

## New Files

| Layer | File | Purpose |
|-------|------|---------|
| SonoBarKit | `Models/AudibleModels.swift` | AudibleBook, AudibleChapter structs |
| SonoBarKit | `Services/AudibleClient.swift` | HTTP client for Audible API |
| SonoBarKit | `Services/AudibleAuth.swift` | OAuth PKCE flow with local callback server |
| SonoBarKit | `Tests/.../AudibleModelsTests.swift` | JSON parsing tests |
| SonoBarKit | `Tests/.../AudibleClientTests.swift` | API endpoint tests |
| SonoBar | `Services/AudibleKeychain.swift` | Keychain for auth tokens |
| SonoBar | `Services/SonosAudibleParams.swift` | Discover/store Sonos service params |
| SonoBar | `Views/AudibleBrowseView.swift` | Main Audible tab with continue listening + library |
| SonoBar | `Views/AudibleChapterView.swift` | Chapter list for a book |
| SonoBar | `Views/AudibleSetupView.swift` | Sign in with Amazon flow |

### Modified Files

- `AppState.swift` — AudibleClient lifecycle, playback methods, service param discovery
- `BrowseView.swift` — add Audible segment to picker
- `NowPlayingView.swift` — update `sourceBadge` for Audible URI detection

## Testing

### SonoBarKit Tests

- **AudibleModelsTests** — parse sample Audible API JSON responses
- **AudibleClientTests** — verify URL construction, token headers, endpoint paths

### Manual Testing

- Sign in with Amazon via browser
- Browse library with cover art
- View chapters for a book
- Play a book on Sonos speaker
- Resume from saved position
- Jump to specific chapter
- Verify Sonos handles chapter navigation (next/previous)
- Token refresh after expiry
- Service param discovery from speakers

## Out of Scope

- Downloading/converting Audible content (DRM)
- Progress reporting to Audible (Sonos handles this natively)
- Wishlist/store browsing
- Multiple marketplace support (hardcoded to `co.uk`)
- Audible podcasts
