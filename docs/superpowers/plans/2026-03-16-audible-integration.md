# Audible Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Audible audiobook browsing, chapter navigation, and playback to SonoBar via the Audible API and Sonos's built-in Audible service.

**Architecture:** AudibleClient (SonoBarKit) talks to Audible's REST API with RSA-signed requests for browsing/chapters/resume. AudibleAuth handles OAuth PKCE + device registration via WKWebView. Playback constructs Sonos `x-rincon-cpcontainer:` URIs with the book's ASIN and Audible service params discovered from speakers.

**Tech Stack:** Swift, SwiftUI, WebKit (WKWebView for auth), Security.framework (RSA signing + Keychain), CryptoKit (SHA256)

**Spec:** `docs/superpowers/specs/2026-03-16-audible-integration-design.md`

---

## File Map

### New Files (SonoBarKit)

| File | Responsibility |
|------|---------------|
| `SonoBarKit/Sources/SonoBarKit/Models/AudibleModels.swift` | AudibleBook, AudibleChapter, AudibleListeningPosition + JSON parsing |
| `SonoBarKit/Sources/SonoBarKit/Services/AudibleClient.swift` | HTTP client for Audible API with request signing |
| `SonoBarKit/Sources/SonoBarKit/Services/AudibleAuth.swift` | PKCE generation, request signing, token refresh |
| `SonoBarKit/Tests/SonoBarKitTests/Models/AudibleModelsTests.swift` | JSON parsing tests |
| `SonoBarKit/Tests/SonoBarKitTests/Services/AudibleClientTests.swift` | API endpoint + signing tests |

### New Files (SonoBar app)

| File | Responsibility |
|------|---------------|
| `SonoBar/Services/AudibleKeychain.swift` | Keychain for access token, refresh token, adp_token, RSA key, device serial |
| `SonoBar/Services/SonosAudibleParams.swift` | Discover/store Sonos service params from speakers |
| `SonoBar/Views/AudibleBrowseView.swift` | Main Audible tab: continue listening + library grid + search |
| `SonoBar/Views/AudibleChapterView.swift` | Chapter list with resume/play/chapter-jump |
| `SonoBar/Views/AudibleSetupView.swift` | WKWebView-based Amazon sign-in + device registration |

### Modified Files

| File | Changes |
|------|---------|
| `SonoBar/Services/AppState.swift` | AudibleClient lifecycle, Audible playback methods, Sonos param discovery in refreshAllRooms |
| `SonoBar/Views/BrowseView.swift` | Add Audible segment to Recents \| Plex \| Audible picker |
| `SonoBar/Views/NowPlayingView.swift` | Update `sourceBadge` to detect Audible via media URI `sid=239` |
| `SonoBar.xcodeproj/project.pbxproj` | Add new files to build |

---

## Chunk 1: Models + Auth Infrastructure

### Task 1: Audible Models with JSON Parsing

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Models/AudibleModels.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Models/AudibleModelsTests.swift`

The Audible API returns nested JSON. Key mappings:
- Library: `response.items[]` → `AudibleBook`
- Book authors: `items[].authors[0].name` → `author`
- Book narrators: `items[].narrators[0].name` → `narrator`
- Cover art: `items[].product_images.500` → `coverURL`
- Duration: `items[].runtime_length_ms` → `durationMs`
- Chapters: `items[].chapter_info.chapters[]` → `[AudibleChapter]`
- Listening positions: `response[].last_position_ms` → `AudibleListeningPosition`

**Models to implement:**

```swift
// AudibleBook — custom Codable for nested JSON
struct AudibleBook: Identifiable, Sendable {
    let asin: String
    let title: String
    let author: String
    let narrator: String?
    let coverURL: String?
    let durationMs: Int
    let purchaseDate: Date?
    var id: String { asin }
}

// AudibleChapter
struct AudibleChapter: Identifiable, Sendable, Codable {
    let index: Int
    let title: String
    let startOffsetMs: Int
    let durationMs: Int
    var id: Int { index }
}

// AudibleListeningPosition
struct AudibleListeningPosition: Sendable {
    let asin: String
    let positionMs: Int
}
```

**Tests:**
1. `testAudibleBookParsesFromJSON` — verify nested author/narrator/coverURL extraction
2. `testAudibleChapterParsesFromJSON` — verify chapter fields
3. `testAudibleBookHandlesMissingOptionals` — narrator nil, coverURL nil
4. `testAudibleListeningPositionParsesFromJSON` — verify position extraction

- [ ] **Step 1: Write failing tests**
- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SonoBarKit && swift test --filter AudibleModelsTests 2>&1 | tail -5`

- [ ] **Step 3: Implement models**
- [ ] **Step 4: Run tests to verify they pass**
- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Models/AudibleModels.swift SonoBarKit/Tests/SonoBarKitTests/Models/AudibleModelsTests.swift
git commit -m "feat: add Audible data models with JSON parsing"
```

---

### Task 2: AudibleAuth — PKCE + Request Signing

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/AudibleAuth.swift`

This file handles three things:
1. PKCE code verifier/challenge generation
2. Request signing (RSA SHA256 + adp_token)
3. Token refresh

**PKCE generation:**
```swift
static func createCodeVerifier() -> String
// 32 random bytes → base64url-encoded (no padding)

static func createCodeChallenge(verifier: String) -> String
// SHA256(verifier) → base64url-encoded (no padding)
```

**OAuth URL construction (UK marketplace):**
```swift
static func buildAuthURL(clientId: String, codeChallenge: String) -> URL
// https://www.amazon.co.uk/ap/signin?
//   openid.oa2.response_type=code
//   &openid.oa2.code_challenge_method=S256
//   &openid.oa2.code_challenge={challenge}
//   &openid.oa2.client_id={clientId}
//   &openid.oa2.scope=device_auth_access
//   &openid.return_to=https://www.amazon.co.uk/ap/maplanding
//   &openid.assoc_handle=amzn_audible_ios_uk
//   &marketPlaceId=A2I9A3Q2GNFNGQ
//   &pageId=amzn_audible_ios
//   &openid.mode=checkid_setup
//   &openid.ns=http://specs.openid.net/auth/2.0
//   &openid.claimed_id=http://specs.openid.net/auth/2.0/identifier_select
//   &openid.identity=http://specs.openid.net/auth/2.0/identifier_select
```

**Device registration request builder:**
```swift
static func buildRegistrationRequest(authCode: String, codeVerifier: String, clientId: String, deviceSerial: String) -> URLRequest
// POST https://api.amazon.co.uk/auth/register
// JSON body with auth_data, registration_data, requested_token_type, etc.
```

**Request signing:**
```swift
static func signRequest(_ request: inout URLRequest, adpToken: String, privateKeyPEM: String)
// Signing string: "{method}\n{path}\n{isoTimestamp}\n{body}\n{adpToken}"
// Sign with SHA256withRSA using the private key
// Add headers: x-adp-token, x-adp-alg, x-adp-signature (signature:timestamp)
```

Uses `Security.framework` for RSA signing (`SecKeyCreateSignature`) and `CryptoKit` for SHA256.

**Tests (in AudibleClientTests or a new AudibleAuthTests):**
1. `testCodeVerifierIsBase64URL` — verify 32-byte output, no padding
2. `testCodeChallengeIsSHA256` — verify known input/output pair
3. `testAuthURLContainsRequiredParams` — verify all query params present
4. `testRegistrationRequestBody` — verify JSON structure
5. `testSignRequestAddsHeaders` — verify x-adp-token, x-adp-alg, x-adp-signature headers

- [ ] **Step 1: Write failing tests**
- [ ] **Step 2: Implement AudibleAuth**

Key implementation notes:
- Use `SecKeyCreateWithData` to import PEM private key
- Use `SecKeyCreateSignature` with `.rsaSignatureMessagePKCS1v1SHA256` for signing
- PEM key from registration response needs `-----BEGIN RSA PRIVATE KEY-----` header/footer stripped and base64-decoded before creating `SecKey`

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/AudibleAuth.swift SonoBarKit/Tests/SonoBarKitTests/Services/AudibleAuthTests.swift
git commit -m "feat: add AudibleAuth with PKCE, request signing, and registration"
```

---

### Task 3: AudibleClient HTTP Client

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/AudibleClient.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/Services/AudibleClientTests.swift`

**API methods:**
```swift
public final class AudibleClient: Sendable {
    let marketplace: String  // "co.uk"

    init(marketplace: String, adpToken: String, privateKeyPEM: String, accessToken: String, httpClient: HTTPClientProtocol)

    func getLibrary() async throws -> [AudibleBook]
    func getChapters(asin: String) async throws -> [AudibleChapter]
    func getListeningPositions(asins: [String]) async throws -> [AudibleListeningPosition]
    func coverURL(path: String) -> URL?
}
```

Each request:
1. Build URL from `https://api.audible.{marketplace}/1.0/...`
2. Sign with `AudibleAuth.signRequest`
3. Parse JSON response
4. Handle errors (401 → token expired, network → unreachable)

Uses `HTTPClientProtocol` for testability (same as SOAPClient and PlexClient).

**Tests:**
1. `testGetLibrarySendsCorrectPath` — verify URL and signing headers
2. `testGetChaptersSendsASIN` — verify ASIN in path
3. `testGetListeningPositionsSendsASINs` — verify comma-separated ASINs in query
4. `testUnauthorizedThrowsError` — verify 401 handling

- [ ] **Step 1: Write failing tests**
- [ ] **Step 2: Implement AudibleClient**
- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/AudibleClient.swift SonoBarKit/Tests/SonoBarKitTests/Services/AudibleClientTests.swift
git commit -m "feat: add AudibleClient HTTP client with request signing"
```

---

## Chunk 2: Keychain + Sonos Params + Setup UI

### Task 4: AudibleKeychain

**Files:**
- Create: `SonoBar/Services/AudibleKeychain.swift`

Same pattern as `PlexKeychain.swift` but stores five values:
- `accessToken`
- `refreshToken`
- `adpToken`
- `privateKeyPEM`
- `deviceSerial`

All under service `com.sonobar.audible` with different account keys.

- [ ] **Step 1: Implement AudibleKeychain**
- [ ] **Step 2: Commit**

---

### Task 5: SonosAudibleParams — Service Parameter Discovery

**Files:**
- Create: `SonoBar/Services/SonosAudibleParams.swift`

Discovers and stores: `sid` (239), `sn`, `desc` token, marketplace suffix.

**Discovery logic:** Scan `roomStates` for any media URI containing `sid=239`:
```swift
static func discover(from roomStates: [String: RoomSummary]) -> SonosAudibleParams?
// 1. Find any summary where mediaURI contains "sid=239"
// 2. Parse sn from URI query string
// 3. Parse marketplace from URI (e.g., "_co.uk" suffix in the item ID)
// 4. Extract desc from mediaDIDL (parse the <desc> element)
// 5. Store in UserDefaults
```

Also provide:
```swift
func buildPlayURI(asin: String) -> String
func buildPlayDIDL(asin: String, title: String, coverURL: String?) -> String
```

- [ ] **Step 1: Implement SonosAudibleParams**
- [ ] **Step 2: Commit**

---

### Task 6: AudibleSetupView — WKWebView Amazon Sign-in

**Files:**
- Create: `SonoBar/Views/AudibleSetupView.swift`

Shows either:
- **Connected state**: account info, Disconnect button
- **Setup state**: "Sign in with Amazon" button

When user taps sign in:
1. Generate device serial, code verifier/challenge, client ID
2. Present a sheet containing a `WKWebView` pointed at the Amazon OAuth URL
3. WKWebView's `WKNavigationDelegate` watches for redirect to `maplanding`
4. Extract auth code from the redirect URL
5. Call device registration endpoint
6. Parse response: extract tokens, adp_token, RSA key
7. Store all in Keychain
8. Create AudibleClient and connect

Note: WKWebView requires `import WebKit` and is an AppKit/UIKit view — use `NSViewRepresentable` to wrap it in SwiftUI.

- [ ] **Step 1: Implement AudibleSetupView**
- [ ] **Step 2: Verify build**

Run: `xcodebuild -scheme SonoBar -configuration Debug build 2>&1 | tail -5`

- [ ] **Step 3: Commit**

---

## Chunk 3: AppState Integration + Playback

### Task 7: AppState Audible Lifecycle + Playback

**Files:**
- Modify: `SonoBar/Services/AppState.swift`

Add to AppState (new `// MARK: - Audible Integration` section):

**Properties:**
```swift
private(set) var audibleClient: AudibleClient?
var audibleBooks: [AudibleBook] = []
var audibleChapters: [AudibleChapter] = []
var audibleOnDeck: [(book: AudibleBook, position: AudibleListeningPosition)] = []
var audibleError: String?
var isAudibleLoading = false
var sonosAudibleParams: SonosAudibleParams?
```

**Lifecycle methods:**
```swift
func connectAudible(marketplace:, adpToken:, privateKeyPEM:, accessToken:, refreshToken:, deviceSerial:)
func disconnectAudible()
func initAudibleIfConfigured()  // called from startDiscovery
func loadAudibleLibrary() async
func loadAudibleChapters(asin:) async
func loadAudibleOnDeck() async  // library + listening positions
func searchAudible(query:) // client-side filter
```

**Playback methods:**
```swift
func playAudibleBook(book: AudibleBook, seekOffsetMs: Int = 0) async
// 1. Check sonosAudibleParams exist
// 2. Build URI + DIDL from ASIN
// 3. SetAVTransportURI + Play
// 4. If seekOffsetMs > 0: waitForPlaying, then Seek, then verify position

func playAudibleChapter(book: AudibleBook, chapter: AudibleChapter) async
// Same as above but with chapter.startOffsetMs as seek target
```

**Sonos param discovery** — add to `refreshAllRooms()`:
```swift
// After setting roomStates, try to discover Audible params
if sonosAudibleParams == nil {
    sonosAudibleParams = SonosAudibleParams.discover(from: coordinatorSummaries, roomStates: newStates)
}
```

Note: `SonosAudibleParams.discover` needs access to the DIDL metadata. `RoomSummary` already has `mediaDIDL` from the earlier rooms update.

- [ ] **Step 1: Add Audible properties and lifecycle methods**
- [ ] **Step 2: Add playback methods**
- [ ] **Step 3: Add Sonos param discovery to refreshAllRooms**
- [ ] **Step 4: Call initAudibleIfConfigured in startDiscovery**
- [ ] **Step 5: Build and test**
- [ ] **Step 6: Commit**

---

## Chunk 4: Browse UI

### Task 8: AudibleBrowseView

**Files:**
- Create: `SonoBar/Views/AudibleBrowseView.swift`

Same pattern as `PlexBrowseView`:
- If not connected → show `AudibleSetupView`
- If no Sonos params → show "Play any Audible book from the Sonos app once, then try again here"
- Otherwise show:
  - Search bar (client-side filtering)
  - Continue Listening section (books with positions, sorted by purchase date)
  - Library grid (3-column, same as Plex)
- Navigation: tap book → push `AudibleChapterView`
- Reuse `PlexArtworkView` pattern for cover art (via `ArtworkCache.shared`)

- [ ] **Step 1: Implement AudibleBrowseView**
- [ ] **Step 2: Commit**

---

### Task 9: AudibleChapterView

**Files:**
- Create: `SonoBar/Views/AudibleChapterView.swift`

Shows:
- Book header: cover art, title, author, total duration
- Resume button (if listening position exists) + Play All button
- Chapter list: index, title, duration, progress bar on in-progress chapter
- Tap chapter → `appState.playAudibleChapter(book:chapter:)`

- [ ] **Step 1: Implement AudibleChapterView**
- [ ] **Step 2: Commit**

---

### Task 10: Wire Audible into BrowseView + Source Badge

**Files:**
- Modify: `SonoBar/Views/BrowseView.swift`
- Modify: `SonoBar/Views/NowPlayingView.swift`

**BrowseView**: Add `.audible` case to `BrowseSegment`:
```swift
enum BrowseSegment: String, CaseIterable {
    case recents = "Recents"
    case plex = "Plex"
    case audible = "Audible"
}
```

**NowPlayingView sourceBadge**: Check media URI for `sid=239`:
```swift
if let mediaURI = appState.playbackState.currentTrack?.uri,
   mediaURI.contains("sid=239") { return "Audible" }
```

Note: for Audible content, the track URI is `x-sonosapi-hls-static:...?sid=239` so checking the track URI for `sid=239` should work. If not, we'd need to also check the media URI which requires storing it somewhere accessible.

- [ ] **Step 1: Update BrowseView**
- [ ] **Step 2: Update sourceBadge**
- [ ] **Step 3: Commit**

---

### Task 11: Add Files to Xcode Project + Build Verification

**Files:**
- Modify: `SonoBar.xcodeproj/project.pbxproj`

Add all new SonoBar files:
- `SonoBar/Services/AudibleKeychain.swift`
- `SonoBar/Services/SonosAudibleParams.swift`
- `SonoBar/Views/AudibleBrowseView.swift`
- `SonoBar/Views/AudibleChapterView.swift`
- `SonoBar/Views/AudibleSetupView.swift`

- [ ] **Step 1: Add files to Xcode project**
- [ ] **Step 2: Build**: `xcodebuild -scheme SonoBar -configuration Debug build 2>&1 | tail -5`
- [ ] **Step 3: Run tests**: `cd SonoBarKit && swift test 2>&1 | tail -5`
- [ ] **Step 4: Commit**

---

### Task 12: Manual Testing Checklist

- [ ] Go to Browse → Audible tab
- [ ] Verify setup view appears
- [ ] Sign in with Amazon via WKWebView
- [ ] Verify library loads with cover art
- [ ] Search for a book by title
- [ ] Tap a book → verify chapter list loads
- [ ] Tap "Play All" → verify playback starts on Sonos
- [ ] Check Now Playing shows book title and "Audible" source badge
- [ ] Tap "Resume" → verify seek to saved position
- [ ] Tap a specific chapter → verify seek to chapter offset
- [ ] Verify Sonos next/previous navigate chapters
- [ ] Stop playback, switch to Rooms tab, verify Audible content visible in room status
- [ ] Close and reopen app → verify Audible stays connected (tokens in Keychain)
- [ ] Wait >1 hour → verify token refresh works transparently
