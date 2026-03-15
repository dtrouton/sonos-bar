# SonoBar

A macOS menu bar app for controlling Sonos speakers, with deep Plex Media Server integration.

Built with Swift/SwiftUI. Talks directly to Sonos speakers via UPnP/SOAP and to Plex via its HTTP API — no cloud dependencies, everything runs on your local network.

## Features

### Now Playing
- Album art, track info, and source badge (Spotify, Apple Music, Plex, BBC Sounds, etc.)
- Play/pause, next/previous, scrubbable progress bar
- Volume control with mute toggle
- Inline queue viewer — tap the list icon to see and jump between tracks
- Sleep timer with countdown — tap the moon icon to set 15/30/45/60 minute timers
- Live progress updates (1-second polling)
- TV and Line-In detection for home theater speakers

### Room Switching
- See all Sonos speakers with current playback status and album art
- Tap a room to switch control and jump to Now Playing
- Group/ungroup speakers
- Shows TV, Line-In, or track info per room

### Plex Integration
- Browse Audiobooks and Music libraries from your Plex server
- **Continue Listening** — resume audiobooks exactly where you left off
- Search across all Plex libraries (scoped when inside a library)
- Album art throughout
- Bi-directional progress sync — listen on Sonos, pick up on your phone
- Plex OAuth sign-in (no manual token copying)
- Auto-discovery of Plex servers on your network

### Browse (Recents)
- Recently played content with artwork
- One-tap replay for radio streams and direct-URI content
- Search/filter recents

### Alarms
- View, create, toggle, and delete Sonos alarms
- Per-room alarm management

### Media Keys
- Play/pause, next, previous via keyboard media keys
- Now Playing info in macOS media controls

## Architecture

```
SonoBar (macOS app)
├── Views/          — SwiftUI views (Now Playing, Rooms, Browse, Plex, Alarms)
├── Services/       — AppState (@Observable), PlexKeychain
├── Controllers/    — MediaKeyController
└── Persistence/    — ArtworkCache (memory + disk LRU)

SonoBarKit (Swift Package)
├── Models/         — Sonos models, Plex models, DIDL parser
├── Services/       — PlaybackController, PlexClient, ContentBrowser, AlarmScheduler
└── Network/        — SOAPClient, UPnP event listener, SSDP discovery
```

## Requirements

- macOS 14+
- Sonos speakers on the local network
- Plex Media Server (optional, for Plex integration)

## Setup

1. Clone and open `SonoBar.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. SonoBar appears in the menu bar — click to open
4. Speakers are discovered automatically via SSDP

### Plex Setup
1. Go to Browse tab → Plex
2. The app scans your network for Plex servers
3. Click "Sign in with Plex" — authorise in your browser
4. Your Audiobooks and Music libraries appear automatically

## License

MIT
