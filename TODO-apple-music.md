# Apple Music Integration — TODO

## Prerequisites
- [ ] Enroll in Apple Developer Program ($99/yr) at developer.apple.com/programs
- [ ] Enable MusicKit entitlement for bundle ID in developer portal
- [ ] Add `NSAppleMusicUsageDescription` to Info.plist

## Implementation Steps

### 1. Service Discovery
- Query Sonos MusicServices SOAP endpoint to find Apple Music account serial number (`sn`)
- Similar to how `SonosAudibleParams` discovers Audible's `sid`/`sn` from room state
- Apple Music service ID on Sonos: `sid=204`, service type: `52231`

### 2. MusicKit Library Browsing
- `MusicAuthorization.request()` for user consent
- `MusicLibraryRequest<Album>` / `<Song>` / `<Playlist>` for library browsing
- `MusicCatalogSearchRequest` for search
- `MusicDataRequest` to `/v1/me/recent/played` for recently played
- Requires macOS 14+ (already our target)

### 3. Sonos URI Construction
- Song: `x-sonos-http:song%3a{ID}.mp4?sid=204&flags=8224&sn={SN}`
- Album: `x-rincon-cpcontainer:1004206calbum%3a{ID}`
- Playlist: `x-rincon-cpcontainer:1006206cplaylist%3a{ID}`
- DIDL metadata with `SA_RINCON52231_X_#Svc52231-0-Token` descriptor

### 4. UI
- Apple Music tab alongside Audible in browse view
- Search, library, playlists, recently played sections
- Album/playlist detail views with track lists

## Key References
- SoCo Python library (github.com/SoCo/SoCo) — full Apple Music URI/DIDL support
- node-sonos-http-api `appleDef.js` — URI construction reference
- MusicKit docs: developer.apple.com/documentation/musickit

## Notes
- MusicKit IDs (`Song.id`, `Album.id`) map directly to Sonos URI IDs
- Library-only items may use `l.`-prefixed IDs — needs testing
- No manual auth/token management needed — OS handles it all
- Cannot test MusicKit in Simulator, requires real Mac
