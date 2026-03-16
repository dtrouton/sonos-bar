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

HTTP client for the Audible REST API. Handles library browsing, chapter info, resume positions, and cover art URLs. Requests are signed using RSA + `adp_token` (Audible's device authentication scheme).

Base URL: `https://api.audible.co.uk` (marketplace-specific)

### SonosAudibleParams

Discovers Audible-specific Sonos service parameters by scanning speaker URIs. Stores `sid`, `sn`, marketplace suffix, and `desc` token in UserDefaults. These are needed to construct playback URIs from ASINs.

Discovery sources (in priority order):
1. Room scan — extract from any `x-rincon-cpcontainer:...?sid=239` URI and its DIDL `desc` element
2. MusicServices SOAP query — `GetSessionId` action with service ID 239 returns the account serial number. The `desc` token follows the pattern `SA_RINCON{serviceAccountId}_X_#Svc{serviceAccountId}-0-Token` where `serviceAccountId` is returned by the MusicServices service.

### Audible Browse UI (SonoBar)

New segment in Browse tab: **Recents | Plex | Audible**

## AudibleClient API

```
AudibleClient
├── getLibrary() -> [AudibleBook]
├── getBook(asin:) -> AudibleBook
├── getChapters(asin:) -> [AudibleChapter]
├── getListeningPositions(asins:) -> [AudibleListeningPosition]
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
| `refreshTokensIfNeeded` | `POST https://api.amazon.co.uk/auth/o2/token` with refresh token |

### Request Signing

All API requests are signed using the device's RSA private key and `adp_token` (not bearer tokens — bearer auth is unreliable on UK marketplace). Each request includes:
- `x-adp-token: {adp_token}`
- `x-adp-alg: SHA256withRSA:1.0`
- `x-adp-signature: {signature}`

The signature is computed as `SHA256withRSA(method + "\n" + path + "\n" + timestamp + "\n" + body + "\n" + adp_token)` using the stored RSA private key.

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
    let index: Int                // chapter number (0-based)
    let title: String
    let startOffsetMs: Int
    let durationMs: Int
    var id: Int { index }
}

struct AudibleListeningPosition: Sendable {
    let asin: String
    let positionMs: Int
}
```

## Authentication

Amazon OAuth with PKCE, followed by device registration. Amazon does not redirect to localhost — the auth uses a WKWebView to capture the redirect URL.

### Flow

1. Generate `code_verifier` (random 32 bytes, base64url-encoded) and `code_challenge` (SHA256 of verifier, base64url-encoded)
2. Generate a `device_serial` (random hex string, stored for reuse)
3. Construct `client_id` as `"device:{device_serial}#A2CZJZGLK2JJVM"`
4. Open a `WKWebView` (in-app, not external browser) to:
   ```
   https://www.amazon.co.uk/ap/signin?
     client_id={client_id}
     &response_type=code
     &code_challenge={challenge}
     &code_challenge_method=S256
   ```
5. User logs in (WKWebView handles 2FA/CAPTCHA natively)
6. Amazon redirects to `https://www.amazon.co.uk/ap/maplanding?...code={auth_code}`
7. WKWebView's navigation delegate intercepts the redirect URL and extracts the code
8. **Device Registration** — exchange code for device credentials:
   ```
   POST https://api.amazon.co.uk/auth/register
   {
     "auth_data": {
       "authorization_code": "{auth_code}",
       "code_verifier": "{verifier}",
       "code_algorithm": "SHA-256",
       "client_domain": "DeviceLegacy",
       "client_id": "{client_id}"
     },
     "registration_data": {
       "domain": "Device",
       "app_version": "3.56.2",
       "device_type": "A2CZJZGLK2JJVM",
       "device_serial": "{device_serial}",
       "app_name": "Audible",
       "os_version": "17.0",
       "software_version": "35602678"
     },
     "requested_token_type": [
       "bearer",
       "mac_dms",
       "store_authentication_cookie",
       "website_cookies"
     ],
     "cookies": { "domain": ".amazon.co.uk", "website_cookies": [] },
     "requested_extensions": ["device_info", "customer_info"]
   }
   ```
9. Response includes:
   - `access_token` (short-lived ~1 hour)
   - `refresh_token` (long-lived)
   - `mac_dms.adp_token` (for request signing)
   - `mac_dms.device_private_key` (RSA private key PEM)
10. Store all four in Keychain

### Token Refresh

Access tokens expire after ~1 hour. Before each API call, check expiry. If expired:
```
POST https://api.amazon.co.uk/auth/o2/token
  grant_type=refresh_token
  &refresh_token={refresh_token}
  &client_id={client_id}
```

The `adp_token` and RSA key do not expire and do not need refreshing.

### Constants (UK Marketplace)

- Device type: `A2CZJZGLK2JJVM`
- Domain: `amazon.co.uk`
- API base: `https://api.audible.co.uk`

## Sonos Service Parameters

### Discovery

On each `refreshAllRooms`, scan `roomStates` for Audible URIs:

```swift
// When mediaURI contains "sid=239"
// Extract: sn from query string, marketplace from URI suffix (_co.uk)
// Extract: desc from DIDL metadata (stored in mediaDIDL on RoomSummary)
```

Store in UserDefaults:
- `audibleSonosSID` = `239`
- `audibleSonosSN` = `6`
- `audibleSonosDesc` = `SA_RINCON61191_X_#Svc61191-0-Token`
- `audibleMarketplace` = `co.uk`

### Fallback: MusicServices Query

If no speaker has Audible content loaded, query the Sonos `MusicServices` SOAP service. Call `GetSessionId` with `ServiceId=239` to get the account-specific session info. The `desc` token can be constructed from the service account ID returned.

### Stale Params

If playback fails with a SOAP error after using stored params, clear UserDefaults and re-discover on next room scan. Show "Play any Audible book from the Sonos app once, then try again" if discovery fails.

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
│ Library (sorted by purchase) │
│ ┌───┐ ┌───┐ ┌───┐           │
│ │   │ │   │ │   │           │
│ └───┘ └───┘ └───┘           │
│ Title  Title  Title          │
└──────────────────────────────┘
```

### Continue Listening

- Fetch library, then batch-fetch listening positions via `getListeningPositions`
- Show books with position > 0, sorted by purchase date (the API does not return a "last listened" timestamp)
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
- Play All: starts from beginning
- Tap chapter: plays from that chapter's start offset
- Progress bar on the currently-in-progress chapter

### Error States

- **Not connected**: Show setup view (Sign in with Amazon)
- **Sonos params not found**: "Play any Audible book from the Sonos app once, then try again here"
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
2. Wait for `PLAYING` state (same `waitForPlaying` pattern as Plex — poll every 250ms, max 5 seconds)
3. Seek to the target offset via `AVTransport.Seek` with `REL_TIME`
4. **Verify seek**: poll `GetPositionInfo` after seek to confirm position changed. If not, retry once. If still wrong, log a warning but don't block playback.

For resume: offset from `getListeningPositions` API.
For chapter jump: offset from `getChapters` API (`startOffsetMs`).

**Risk**: Chapter seeking on Audible via Sonos is known to be unreliable in the Sonos community. The seek may silently fail or land in the wrong position. The verify-and-retry approach mitigates this. If seek is consistently unreliable, a future improvement could use repeated `Next` track calls to step through chapters instead.

### Progress Reporting

Not needed via Audible API — Sonos reports progress to Audible directly through its built-in service integration. The Audible app and API will reflect updated positions automatically.

## New Files

| Layer | File | Purpose |
|-------|------|---------|
| SonoBarKit | `Models/AudibleModels.swift` | AudibleBook, AudibleChapter structs |
| SonoBarKit | `Services/AudibleClient.swift` | HTTP client for Audible API with request signing |
| SonoBarKit | `Services/AudibleAuth.swift` | OAuth PKCE + device registration + RSA signing |
| SonoBarKit | `Tests/.../AudibleModelsTests.swift` | JSON parsing tests |
| SonoBarKit | `Tests/.../AudibleClientTests.swift` | API endpoint tests |
| SonoBar | `Services/AudibleKeychain.swift` | Keychain for access token, refresh token, adp_token, RSA key |
| SonoBar | `Services/SonosAudibleParams.swift` | Discover/store Sonos service params |
| SonoBar | `Views/AudibleBrowseView.swift` | Main Audible tab with continue listening + library |
| SonoBar | `Views/AudibleChapterView.swift` | Chapter list for a book |
| SonoBar | `Views/AudibleSetupView.swift` | WKWebView-based Amazon sign-in |

### Modified Files

- `AppState.swift` — AudibleClient lifecycle, playback methods, service param discovery
- `BrowseView.swift` — add Audible segment to picker
- `NowPlayingView.swift` — update `sourceBadge` to check media URI for `sid=239` (not track URI for "audible")

## Testing

### SonoBarKit Tests

- **AudibleModelsTests** — parse sample Audible API JSON responses
- **AudibleClientTests** — verify URL construction, request signing, endpoint paths
- **AudibleAuthTests** — verify PKCE challenge generation, device registration request format

### Manual Testing

- Sign in with Amazon via WKWebView
- Browse library with cover art
- View chapters for a book
- Play a book on Sonos speaker
- Resume from saved position
- Jump to specific chapter
- Verify seek position after chapter jump
- Verify Sonos handles chapter navigation (next/previous)
- Token refresh after expiry
- Service param discovery from speakers

## Out of Scope

- Downloading/converting Audible content (DRM)
- Progress reporting to Audible (Sonos handles this natively)
- Wishlist/store browsing
- Multiple marketplace support (hardcoded to `co.uk`)
- Audible podcasts
- Bearer-token auth (unreliable on UK marketplace — using signed requests)
