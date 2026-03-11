# SonoBar - Lightweight Menu Bar Controller for Sonos

## Overview

A native macOS menu bar app for controlling Sonos speakers. Built with Swift + SwiftUI, communicating over the local LAN via UPnP/SOAP. No cloud dependency, no internet required.

**Motivation:** The official Sonos app is heavy and slow. SonoBar is a lightweight alternative that lives in the menu bar and provides instant access to playback controls, room switching, content browsing, and alarm scheduling.

**Target:** macOS 14+ (Sonoma), Swift 5.9+, SwiftUI + AppKit hybrid.

## Architecture

Three layers:

```
┌─────────────────────────────────┐
│   Menu Bar UI (SwiftUI)         │  NSStatusItem + NSPopover
│   - Now Playing view            │
│   - Room Switcher               │
│   - Browse / Favorites          │
│   - Alarms & Scheduling         │
├─────────────────────────────────┤
│   Sonos Service Layer (Swift)   │  Async/await APIs
│   - DeviceManager               │  Discovers & tracks speakers
│   - PlaybackController          │  Play/pause/skip/volume
│   - ContentBrowser              │  Favorites, playlists, SMAPI
│   - AlarmScheduler              │  Alarms, sleep timers, schedules
│   - GroupManager                │  Room grouping/ungrouping
├─────────────────────────────────┤
│   Network Layer (Swift)         │  Foundation networking
│   - SSDPDiscovery               │  UDP multicast, finds speakers
│   - SOAPClient                  │  HTTP+XML to speakers on :1400
│   - UPnPEventListener           │  Subscribe to state changes
└─────────────────────────────────┘
```

**Key decisions:**
- All communication is local LAN only — no cloud, no Sonos Cloud API
- Async/await throughout using modern Swift concurrency
- UPnP event subscriptions instead of polling for real-time state updates
- SwiftUI for popover UI, AppKit for menu bar anchor (NSStatusItem + NSPopover)

## Network Layer

### SSDPDiscovery

- Sends UDP multicast to `239.255.255.250:1900` with search target `urn:schemas-upnp-org:device:ZonePlayer:1`
- Parses responses for speaker IPs, room names, model info, UUIDs
- Runs on app launch and every 30 seconds to detect speakers coming online/offline
- Uses `NWConnection` (Network.framework) for UDP multicast

### SOAPClient

- Sends HTTP POST to `http://<speaker-ip>:1400/<service-path>`
- Each Sonos UPnP service has a control URL (e.g., `/MediaRenderer/AVTransport/Control`)
- Request body: XML SOAP envelope wrapping the action name and parameters
- Response: XML parsed with `XMLParser` or `XMLDocument`
- Single generic method: `callAction(service:action:params:) async throws -> SOAPResponse`
- Covers all 16 UPnP services exposed by Sonos speakers

### UPnPEventListener

- Starts a lightweight HTTP server on a random local port using `NWListener`
- Subscribes to speaker events via HTTP `SUBSCRIBE` requests
- Speakers POST XML event updates when state changes (track change, volume, group topology)
- Auto-renews subscriptions before the 30-minute expiry
- Eliminates polling — the app reacts to changes within milliseconds

## Error Handling

- **Speaker unreachable:** Gray out the room in the Room Switcher, show an inline "Unreachable" status. Continue attempting SSDP discovery to detect when it comes back.
- **SOAP call failure:** Show a brief toast/banner in the popover (e.g., "Couldn't change volume — speaker not responding"). Do not block the UI. Retry once automatically after 2 seconds.
- **Zero speakers discovered:** Show a friendly empty state in the Room Switcher: "No Sonos speakers found on this network" with a manual refresh button.
- **Event listener port conflict:** Try up to 5 random ports. If all fail, fall back to polling at 3-second intervals (degraded mode).
- **General philosophy:** Never block the UI. Show stale data with a visual indicator rather than a loading spinner. Fail gracefully and recover automatically when possible.

## Data Persistence

- **Active room selection:** Persisted in `UserDefaults`. Restored on launch, validated against discovered speakers.
- **Last-seen speaker list:** Cached in `UserDefaults`. Shown immediately on launch (grayed out) while SSDP discovery runs, so the UI is never empty on startup.
- **Album art cache:** On-disk cache in `~/Library/Caches/SonoBar/artwork/`. LRU eviction at 50MB.
- **Global shortcut bindings:** Stored in `UserDefaults`.
- **No database.** `UserDefaults` + file cache is sufficient for this scope.

## Service Layer

### DeviceManager

- Maintains the list of discovered `SonosDevice` models (IP, room name, model, UUID, group ID)
- Listens to `ZoneGroupTopology` events to keep group/room state current
- Publishes changes via `@Observable` for automatic UI updates
- Tracks the "active" speaker — the one the user is currently controlling

### PlaybackController

- Wraps `AVTransport` and `RenderingControl` UPnP services
- Playback: `play()`, `pause()`, `stop()`, `next()`, `previous()`, `seek(to:)`
- Volume: `setVolume(_ level: Int, for:)` (0–100 scale), `setMute(_ muted: Bool, for:)`
- Group volume: when the active speaker is a group coordinator, the volume slider controls the **group volume** via `GroupRenderingControl`. Individual member volumes are not exposed in the UI (matches official Sonos app behavior).
- Subscribes to `AVTransport` events for now-playing metadata (title, artist, album, art URL, progress)
- Album art fetched from `http://<ip>:1400/getaa?...` and cached locally

### ContentBrowser

- **Sonos Favorites** — via `ContentDirectory` service `Browse` action. Reliable, covers all linked services.
- **Sonos Playlists** — same `ContentDirectory` service
- **Queue management** — browse current queue, add/remove/reorder tracks
- **SMAPI browsing (stretch goal)** — via `MusicServices` to list configured services, then SOAP calls to each service's endpoint for catalog browsing. Auth token retrieval is fragile on newer firmware, so this is incremental.
- Returns structured models: `BrowseResult` containing `[ContentItem]` with title, art URL, metadata URI

### AlarmScheduler

- Wraps `AlarmClock` UPnP service
- CRUD: `listAlarms()`, `createAlarm(...)`, `updateAlarm(...)`, `deleteAlarm(id:)`
- Alarm model: time, recurrence (daily/weekdays/weekends/specific days), room, source URI, volume, duration
- Sleep timer: `setSleepTimer(minutes:)`, `getSleepTimer()` via `AVTransport` service
- Alarms run on the speakers themselves — no app-side scheduling needed. The speaker fires the alarm even if the Mac is off.

### GroupManager

- Wraps `AVTransport` for group operations
- `group(speakers:coordinator:)` — joins speakers by calling `SetAVTransportURI` with `x-rincon:<coordinator-uuid>` on each member speaker. The coordinator is the speaker whose queue/stream is shared.
- `ungroup(speaker:)` — removes a speaker from its group via `BecomeCoordinatorOfStandaloneGroup` on the member speaker
- Listens to `ZoneGroupTopology` events for real-time group changes

## UI Design

Menu bar popover: ~320pt wide x ~450pt tall. Four tabs navigated via a bottom tab bar.

### App Lifecycle

- **LSUIElement = true** in Info.plist — no Dock icon, menu bar only
- **Launch at login** via `SMAppService.mainApp.register()` (macOS 13+), toggled in a Preferences view
- **Popover behavior:** Click icon to toggle open/close. Clicking outside the popover dismisses it (standard `NSPopover.Behavior.transient`). Escape key dismisses. Not detachable into a floating window.

### Menu Bar Icon

- Speaker/music glyph in the macOS status bar via `NSStatusItem`
- Click toggles an `NSPopover` anchored to the icon
- Feels like a native macOS utility (similar to Wi-Fi or Bluetooth dropdowns)

### Now Playing (Default Tab)

- **Room selector** at top — shows current room name and group info (e.g., "+ Kitchen"). Tap to navigate to Room Switcher.
- **Album art** — large, centered (~200x200pt)
- **Track info** — title, artist, album. Source badge (e.g., "Apple Music", "BBC Sounds") with service-colored pill
- **Progress bar** — scrubbable, elapsed/remaining time labels
- **Transport controls** — previous, play/pause, next (centered, prominent play button)
- **Volume slider** — with numeric label showing 0–100, speaker icon as mute toggle. Tap the number to type an exact value.

### Room Switcher

- Navigated from room selector tap or Rooms tab
- Lists all rooms with: room icon, room name, playback status (playing track name or "Idle"), group badges
- Active room highlighted
- Tap a room to make it the active controller
- Group indicators show which rooms are linked
- Long-press or secondary click for group/ungroup actions

### Browse

- **Search bar** at top — client-side filtering of already-fetched favorites and playlists (no SOAP calls on each keystroke)
- **Segmented control** below search: Favorites | Playlists | Queue — switches between the three content sections (all three do not fit simultaneously in a 450pt popover)
- **Sonos Favorites** (default segment) — grid layout (3 columns) with artwork thumbnails, title, and service badge. Scrollable.
- **Sonos Playlists** — list layout with artwork, title, track count
- **Current Queue** — track list showing now-playing indicator, drag-to-reorder
- Tap any item to play on the active room
- Stretch: SMAPI service browser with hierarchical drill-down navigation

### Alarms & Schedules

- **Sleep timer** — quick-set buttons (15m, 30m, 45m, 60m, custom) at the top
- **Alarm list** — each alarm shows: time (large), recurrence, room (colored tag), source. Toggle switch to enable/disable.
- **Add Alarm** button opens a form: time picker, day selector, room picker, source picker (from Sonos Favorites), volume slider
- Supports the "play BBC Sounds at 7am weekdays in the bedroom" use case natively via the Sonos alarm model

### Global Keyboard Shortcuts

- **Media keys** (play/pause, next, previous): Integrate via `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` so macOS routes media key events to SonoBar when it is the active "now playing" app. This avoids conflicts with Apple Music/Spotify and does not require Accessibility permissions.
- **Sonos volume up/down:** Custom global hotkeys (configurable, e.g., Option+Up/Down) registered via `NSEvent.addGlobalMonitorForEvents`. These control the active Sonos room's volume, not Mac system volume.
- **Toggle popover:** Custom global hotkey (configurable, e.g., Option+S).
- Requires Accessibility permission only if using `CGEvent` tap fallback (avoided by default).

### Accessibility

- Standard SwiftUI accessibility labels on all controls
- VoiceOver support for transport controls, volume slider (announces numeric value), room list
- Keyboard navigation within the popover via Tab/arrow keys
- Respects system "Reduce Motion" preference for any animations

## Content Access Strategy

| Tier | Source | Reliability | Phase |
|------|--------|-------------|-------|
| 1 | Sonos Favorites | Rock-solid | MVP |
| 1 | Sonos Playlists | Rock-solid | MVP |
| 1 | Current Queue | Rock-solid | MVP |
| 2 | SMAPI catalog browsing | Fragile (auth issues) | Stretch |

Sonos Favorites are the primary content access path. Users add favorites from the official Sonos app (or any controller), and SonoBar plays them. This covers Apple Music playlists, Audible audiobooks, Plex libraries, BBC Sounds stations, and anything else the user has favorited.

Full SMAPI catalog browsing (search Apple Music, browse Audible library, etc.) is technically possible via the local API but auth token retrieval is fragile on newer Sonos firmware. This is a stretch goal to be developed incrementally.

## Target Services

- Apple Music (primary music)
- Audible (audiobooks)
- Plex (personal media library)
- BBC Sounds (radio/podcasts)

All accessible via Sonos Favorites at minimum. Direct browsing via SMAPI is a stretch goal.

## Technical Constraints

- **Local LAN only** — speakers must be on the same network as the Mac
- **UPnP/SOAP is unofficial** — Sonos has never officially documented it, but it has been stable through S1 and S2 firmware and is relied upon by Home Assistant and many automation platforms
- **No Swift Sonos library exists** — we build the UPnP layer from scratch using Foundation networking and the community-maintained API docs at sonos.svrooij.io
- **Event subscription requires a local HTTP server** — the app runs a lightweight listener for UPnP event callbacks
- **macOS sandbox considerations** — the app needs local network access (com.apple.security.network.client and com.apple.security.network.server entitlements)

## Phasing

### Phase 1 — MVP
- Network layer (SSDP discovery, SOAP client, UPnP event listener)
- DeviceManager (discover speakers, track groups, select active room)
- PlaybackController (play/pause/skip/seek, volume 0–100, now-playing metadata, album art)
- GroupManager (group/ungroup rooms)
- Now Playing tab (full transport controls, room selector, volume with numeric display)
- Room Switcher tab (room list with status, tap to switch)
- Menu bar icon, popover lifecycle, launch-at-login
- Global media key integration via MPNowPlayingInfoCenter
- Data persistence (active room, speaker cache, art cache)
- Error handling (unreachable speakers, empty state, graceful degradation)

### Phase 2 — Content & Scheduling
- ContentBrowser (Sonos Favorites, Sonos Playlists, queue management)
- Browse tab (favorites grid, playlists list, queue with reorder, search filter)
- AlarmScheduler (list/create/update/delete alarms, sleep timer)
- Alarms tab (alarm list with toggles, add alarm form, sleep timer buttons)
- Custom global hotkeys for Sonos volume and popover toggle

### Phase 3 — Stretch
- SMAPI catalog browsing for Apple Music, Audible, Plex, BBC Sounds
- Hierarchical service browser in Browse tab
- Drag-to-reorder in queue

## Out of Scope

- iOS/iPadOS version
- Sonos Cloud API integration
- EQ/sound settings adjustment (could be added later)
- Home theater / surround configuration
- Sonos system setup or speaker configuration
- Account management

## Reference

- Sonos UPnP API docs: https://sonos.svrooij.io/
- Sonos API GitHub: https://github.com/svrooij/sonos-api-docs
- SoCo Python library (reference): https://github.com/SoCo/SoCo
- node-sonos-ts (reference): https://github.com/svrooij/node-sonos-ts
- UI mockups: `.superpowers/brainstorm/mockups/ui-mockups.html`
