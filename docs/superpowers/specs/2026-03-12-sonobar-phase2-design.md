# SonoBar Phase 2: Content, Alarms & Media Keys

## Overview

Phase 2 adds three features to the SonoBar menu bar app: a Browse tab for content access, an Alarms & Sleep Timer tab, and media key integration. These build on the Phase 1 foundation (network layer, models, services, app shell with Now Playing and Room Switcher views).

## Browse Tab

### Segments

Three segments via a `Picker` with `.segmented` style: **Favorites** (default) | **Playlists** | **Queue**.

Favorites is the primary content access path. Users add favorites from the official Sonos app (or any controller), and SonoBar plays them. This covers Apple Music playlists, Audible audiobooks, Plex libraries, BBC Sounds stations, and anything else the user has favorited.

### Search

A search bar at the top of the tab performs client-side filtering across whichever segment is active. Content is fetched once when the tab opens (or segment changes), then filtered locally — no SOAP calls per keystroke.

### Favorites

- Fetched via `ContentDirectory` service `Browse` action with ObjectID `FV:2` (Sonos Favorites)
- Displayed as a 3-column grid with artwork thumbnails and title
- Tap any item to replace the current queue and play immediately on the active room
- Uses `AVTransport` `SetAVTransportURI` with `InstanceID=0`, `CurrentURI=<item resource URI>`, `CurrentURIMetaData=<DIDL-Lite XML>`, then `Play`
- The DIDL-Lite metadata is captured from the Browse response and stored on `ContentItem` for round-tripping (see Content Model)

### Playlists

- Fetched via `ContentDirectory` service `Browse` action with ObjectID `SQ:` (Sonos playlists)
- Displayed as a list with artwork thumbnail, playlist title, and track count
- Tap a playlist to replace the current queue and play immediately
- Uses `AVTransport` `SetAVTransportURI` with `InstanceID=0`, `CurrentURI=<playlist container URI>`, `CurrentURIMetaData=<DIDL-Lite XML>`, then `Play`

### Queue

- Fetched via `ContentDirectory` service `Browse` action with ObjectID `Q:0` on the active room's group coordinator
- Displayed as a list with track number, title, artist, and a now-playing indicator on the current track
- Tap a track to jump to it via `AVTransport` `Seek` with `Unit=TRACK_NR`, `Target=<track number>`
- No drag-to-reorder in this phase

### Content Model

```swift
struct ContentItem: Identifiable, Sendable, Equatable {
    let id: String             // Sonos item ID (e.g., "FV:2/3", "SQ:3")
    let title: String
    let albumArtURI: String?   // Relative URI, prefix with http://<ip>:1400
    let resourceURI: String    // URI to play (x-rincon-cpcontainer:, file:, etc.)
    let rawDIDL: String        // Raw DIDL-Lite XML for this item, used as CurrentURIMetaData
    let itemClass: String      // UPnP class (object.item.audioItem, object.container, etc.)
    let description: String?   // Artist, track count, or other secondary text
}
```

The `rawDIDL` field stores the serialized `<item>` or `<container>` element from the Browse response, wrapped in a minimal DIDL-Lite envelope. This is passed as `CurrentURIMetaData` to `SetAVTransportURI` when playing an item. This round-trip approach avoids needing to reconstruct the DIDL-Lite XML from parsed fields.

### Error Handling

- If `Browse` fails (network error, SOAP fault), the segment shows an inline error message with a **Retry** button
- Empty results show "No favorites found" / "No playlists" / "Queue is empty" with appropriate messaging
- Failed `playItem` shows a brief error banner at the top of the popover (auto-dismiss after 3 seconds)

## Alarms & Sleep Timer Tab

### Sleep Timer (top section)

- Quick-set buttons in a horizontal row: **15m** | **30m** | **45m** | **60m**
- When a timer is active, shows remaining time as a countdown (e.g. "23:45 remaining") and a **Cancel** button
- Uses `AVTransport` service on the active room's coordinator:
  - Set: `ConfigureSleepTimer` with `NewSleepTimerDuration` as `HH:MM:SS`
  - Cancel: `ConfigureSleepTimer` with `NewSleepTimerDuration` as empty string (falls back to `00:00:00` if speaker rejects empty)
  - Get: `GetRemainingSleepTimerDuration` returns `HH:MM:SS` string or empty string if no timer active

### Alarm List (below sleep timer)

- Fetched from `AlarmClock` service `ListAlarms` action (returns XML alarm list)
- Each alarm row shows:
  - Time (large, e.g. "7:00 AM")
  - Recurrence text (e.g. "Weekdays", "Daily", "Mon, Wed, Fri")
  - Room name (from device list, matched by room UUID)
  - Source name (parsed from alarm program URI)
  - Enable/disable toggle switch
- Toggle calls `AlarmClock` `UpdateAlarm` with the alarm's full attributes and toggled `Enabled` flag (1/0)
- Right-click context menu on each alarm for **Edit** and **Delete**
  - Delete calls `AlarmClock` `DestroyAlarm` with `ID=<alarm ID>`

### Add Alarm Form

- **Add Alarm** button at bottom of the alarm list
- Opens an inline form (sheet or expanded section) with:
  - Time picker (hours/minutes, AM/PM)
  - Day selector: checkboxes for each day (Mon through Sun), with "Weekdays" and "Daily" shortcuts
  - Room picker: dropdown populated from `deviceManager.devices`
  - Source picker: dropdown populated from Sonos Favorites (reuses `ContentBrowser.browseFavorites()`)
  - Volume slider (0-100 with numeric display, reuses `VolumeSliderView`)
- Creates alarm via `AlarmClock` `CreateAlarm` action

### Alarm Model

```swift
struct SonosAlarm: Identifiable, Sendable, Equatable {
    let id: String              // Alarm ID from Sonos
    let startLocalTime: String  // "HH:MM:SS" — maps to SOAP param StartLocalTime
    let recurrence: String      // "DAILY", "WEEKDAYS", "WEEKENDS", "ON_0123456"
    let roomUUID: String        // Target speaker UUID
    let programURI: String      // What to play (x-rincon-buzzer:0 for chime, or content URI)
    let programMetaData: String // DIDL-Lite metadata for the source
    let playMode: String        // "NORMAL", "SHUFFLE", "REPEAT_ALL", "SHUFFLE_NOREPEAT"
    let volume: Int             // 0-100
    let duration: String        // How long to play ("01:00:00")
    let enabled: Bool
    let includeLinkedZones: Bool
}
```

### SOAP Parameter Mapping for AlarmClock

`CreateAlarm` and `UpdateAlarm` use these SOAP parameter names (model field → SOAP param):
- `id` → `ID` (UpdateAlarm only)
- `startLocalTime` → `StartLocalTime`
- `duration` → `Duration`
- `recurrence` → `Recurrence`
- `enabled` → `Enabled` (value: `1` or `0`)
- `roomUUID` → `RoomUUID`
- `programURI` → `ProgramURI`
- `programMetaData` → `ProgramMetaData`
- `playMode` → `PlayMode`
- `volume` → `Volume`
- `includeLinkedZones` → `IncludeLinkedZones` (value: `1` or `0`)

### Recurrence Encoding

Sonos uses these recurrence values:
- `DAILY` — every day
- `WEEKDAYS` — Monday through Friday
- `WEEKENDS` — Saturday and Sunday
- `ON_0123456` — specific days (0=Sun, 1=Mon, ..., 6=Sat). e.g. `ON_135` = Mon, Wed, Fri
- `ONCE` — single occurrence

### Error Handling

- If `ListAlarms` fails, show inline error with **Retry** button
- If `CreateAlarm`/`UpdateAlarm`/`DestroyAlarm` fails, show error banner (auto-dismiss)
- Sleep timer set/cancel failures show error banner

## Media Keys

### Behavior

- When the popover **opens**: first publish current track info to `MPNowPlayingInfoCenter`, then register with `MPRemoteCommandCenter` for play/pause, next track, previous track. The info must be published before handlers are registered, or macOS ignores the command registrations.
- When the popover **closes**: unregister all command handlers, clear `nowPlayingInfo`. macOS routes media keys back to the previously active media app (Spotify, Apple Music, etc.).
- While open, keep `MPNowPlayingInfoCenter` updated as track changes occur.

### Implementation

- `MediaKeyController` class in the app target (not SonoBarKit — it depends on `MediaPlayer` framework)
- `activate(track:transportState:)` — publishes now playing info, then registers command targets
- `deactivate()` — removes command targets, clears now playing info
- `updateNowPlaying(track:transportState:)` — updates the info center
- Held by `AppState` (not `AppDelegate`), so `refreshPlayback()` can call `updateNowPlaying` directly
- `AppDelegate` calls `appState.mediaKeyController.activate(...)` on popover show and `deactivate()` on popover close

### Now Playing Info

Published to `MPNowPlayingInfoCenter.default()`:
- `MPMediaItemPropertyTitle` — track title
- `MPMediaItemPropertyArtist` — artist
- `MPMediaItemPropertyAlbumTitle` — album
- `MPNowPlayingInfoPropertyPlaybackRate` — 1.0 if playing, 0.0 if paused/stopped

## SonoBarKit Service Layer Additions

### ContentBrowser

New file: `SonoBarKit/Sources/SonoBarKit/Services/ContentBrowser.swift`

Wraps `ContentDirectory` service (`contentDirectory` in `SonosService` enum). Implemented as an enum with static methods (same pattern as `GroupManager`). All methods take a `SOAPClient` targeting the group coordinator.

```
browseFavorites(client:) async throws -> [ContentItem]
browsePlaylists(client:) async throws -> [ContentItem]
browseQueue(client:) async throws -> [ContentItem]
```

Each calls the SOAP `Browse` action with:
- `ObjectID`: `FV:2` for favorites, `SQ:` for playlists, `Q:0` for queue
- `BrowseFlag`: `BrowseDirectChildren`
- `Filter`: `dc:title,res,upnp:albumArtURI,upnp:class,dc:creator`
- `StartingIndex`: `0`
- `RequestedCount`: `100`
- `SortCriteria`: empty

The response XML is DIDL-Lite; parsed with `DIDLParser` that extracts `ContentItem` instances.

A `playItem(client:item:)` static method calls `SetAVTransportURI` with:
- `InstanceID`: `0`
- `CurrentURI`: `item.resourceURI`
- `CurrentURIMetaData`: `item.rawDIDL`
Then calls `Play` with `InstanceID=0`, `Speed=1`.

### AlarmScheduler

New file: `SonoBarKit/Sources/SonoBarKit/Services/AlarmScheduler.swift`

Wraps `AlarmClock` service. Implemented as an enum with static methods (same pattern as `GroupManager`).

```
listAlarms(client:) async throws -> [SonosAlarm]
createAlarm(client:, alarm: SonosAlarm) async throws
updateAlarm(client:, alarm: SonosAlarm) async throws
deleteAlarm(client:, id: String) async throws
```

`listAlarms` parses the XML response from `ListAlarms` into `[SonosAlarm]`.

`createAlarm` calls `CreateAlarm` with all fields mapped to SOAP parameter names (see SOAP Parameter Mapping above).

`updateAlarm` calls `UpdateAlarm` with alarm ID and all fields.

`deleteAlarm` calls `DestroyAlarm` with `ID` parameter.

### SleepTimerController

New file: `SonoBarKit/Sources/SonoBarKit/Services/SleepTimerController.swift`

Wraps `AVTransport` service for sleep timer operations. Enum with static methods.

```
setSleepTimer(client:, minutes: Int) async throws
getRemainingTime(client:) async throws -> String?   // "HH:MM:SS" or nil if no timer
cancelSleepTimer(client:) async throws
```

`setSleepTimer` converts minutes to `HH:MM:SS` format and calls `ConfigureSleepTimer`.

`getRemainingTime` calls `GetRemainingSleepTimerDuration` and returns the raw `HH:MM:SS` string (nil if empty). The UI layer formats this for display.

`cancelSleepTimer` calls `ConfigureSleepTimer` with empty duration string.

### DIDLParser

New file: `SonoBarKit/Sources/SonoBarKit/Models/DIDLParser.swift`

Parses DIDL-Lite XML (the format Sonos uses for content directory responses) into `[ContentItem]`. Uses `XMLParser` delegate pattern consistent with `ZoneGroupParser` and `XMLResponseParser`. Placed in `Models/` alongside `GroupTopology.swift` since it's Sonos-domain parsing, not generic network code.

For each `<item>` or `<container>` element:
- `id` attribute → `ContentItem.id`
- `<dc:title>` → title
- `<upnp:albumArtURI>` → albumArtURI
- `<res>` text content → resourceURI
- Raw XML of the element wrapped in DIDL-Lite envelope → rawDIDL
- `<upnp:class>` → itemClass
- `<dc:creator>` → description (for tracks), or child count for containers

## App Layer Changes

### AppState Additions

- `var contentItems: [ContentItem] = []` — current browse results
- `var alarms: [SonosAlarm] = []` — fetched alarms
- `var sleepTimerRemaining: String? = nil` — raw HH:MM:SS from speaker, nil if no timer
- `var contentError: String? = nil` — error message for browse failures
- `let mediaKeyController = MediaKeyController()`
- `func browseFavorites() async`
- `func browsePlaylists() async`
- `func browseQueue() async`
- `func playItem(_ item: ContentItem) async`
- `func fetchAlarms() async`
- `func createAlarm(_ alarm: SonosAlarm) async`
- `func toggleAlarm(_ alarm: SonosAlarm) async`
- `func deleteAlarm(_ alarm: SonosAlarm) async`
- `func setSleepTimer(minutes: Int) async`
- `func cancelSleepTimer() async`
- `func refreshSleepTimer() async`

`refreshPlayback()` is extended to also call `mediaKeyController.updateNowPlaying(...)` when media keys are active.

### New Views

- `SonoBar/Views/BrowseView.swift` — search bar, segmented control, content grid/list
- `SonoBar/Views/ContentGridView.swift` — 3-column artwork grid for favorites
- `SonoBar/Views/ContentListView.swift` — list layout for playlists and queue
- `SonoBar/Views/AlarmsView.swift` — sleep timer section + alarm list
- `SonoBar/Views/AlarmFormView.swift` — add/edit alarm form
- `SonoBar/Controllers/MediaKeyController.swift` — media key registration

### PopoverContentView Changes

Replace Browse and Alarms placeholder text with `BrowseView()` and `AlarmsView()`.

### AppDelegate Changes

Add popover show/close hooks to activate/deactivate `MediaKeyController`:

```swift
// In togglePopover():
if popover.isShown {
    popover.performClose(nil)
    appState.mediaKeyController.deactivate()
} else {
    popover.show(...)
    appState.mediaKeyController.activate(
        track: appState.playbackState.currentTrack,
        transportState: appState.playbackState.transportState
    )
}
```

## Testing

### SonoBarKit Tests

Using the same `CapturingHTTPClient` / `MockHTTPClient` pattern:

- **DIDLParserTests** — parse sample DIDL-Lite XML with items and containers, verify ContentItem extraction including rawDIDL capture, handle empty results
- **ContentBrowserTests** — verify correct ObjectIDs sent (`FV:2`, `SQ:`, `Q:0`), verify `playItem` sends correct `SetAVTransportURI` params
- **AlarmSchedulerTests** — verify SOAP actions for list/create/update/delete, verify parameter name mapping, parse alarm list XML
- **SleepTimerControllerTests** — verify timer set/get/cancel SOAP calls, verify HH:MM:SS format conversion

### No UI Tests

Views are not unit tested (same as Phase 1). Verified by running the app.

## File Summary

| Layer | New Files |
|-------|-----------|
| SonoBarKit/Models | `ContentItem.swift`, `SonosAlarm.swift`, `DIDLParser.swift` |
| SonoBarKit/Services | `ContentBrowser.swift`, `AlarmScheduler.swift`, `SleepTimerController.swift` |
| SonoBar/Views | `BrowseView.swift`, `ContentGridView.swift`, `ContentListView.swift`, `AlarmsView.swift`, `AlarmFormView.swift` |
| SonoBar/Controllers | `MediaKeyController.swift` |
| Modified | `AppState.swift`, `AppDelegate.swift`, `PopoverContentView.swift` |
