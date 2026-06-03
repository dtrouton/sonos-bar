# Apple Music — Status

**The Apple Music integration is implemented.** It now uses **MusicKit** for discovery
(catalog search + My Playlists + My Library albums/songs) and the existing Sonos playback path
(constructed `x-rincon-cpcontainer:` / `x-sonos-http:` URIs + an account token extracted from a
Sonos favorite). The earlier iTunes-Search approach has been removed.

See:
- Design: [`docs/superpowers/specs/2026-06-03-apple-music-musickit-rearchitecture-design.md`](docs/superpowers/specs/2026-06-03-apple-music-musickit-rearchitecture-design.md)
- Plan: [`docs/superpowers/plans/2026-06-03-apple-music-musickit-rearchitecture.md`](docs/superpowers/plans/2026-06-03-apple-music-musickit-rearchitecture.md)
- Spike (verified library-playlist playback on a live speaker): [`docs/superpowers/notes/2026-06-03-apple-music-musickit-spike.md`](docs/superpowers/notes/2026-06-03-apple-music-musickit-spike.md)

## Remaining before release (require the developer + hardware)

### 1. MusicKit entitlement & signing (Apple Developer Program)
- [ ] Enable the **MusicKit** App Service for bundle id `com.sonobar.app` at developer.apple.com.
- [ ] Sign the app with a real Development team/profile that includes MusicKit (the project currently
      uses ad-hoc `CODE_SIGN_IDENTITY = "-"`; MusicKit needs a real signed identity at runtime).
- [x] `NSAppleMusicUsageDescription` added to `SonoBar/Info.plist`.
- Note: no special key is required in `SonoBar.entitlements` for user-library MusicKit access — the
  capability lives on the App ID + provisioning profile.

### 2. Manual QA on a real Mac + speaker
- [ ] First launch with a Sonos Apple Music favorite present → macOS prompts for Apple Music access.
- [ ] Deny → "Allow Apple Music access in System Settings"; grant + relaunch → browsing appears.
- [ ] Search returns tracks/albums/artists; tapping a track queues it (verify in the Sonos app).
- [ ] Playlists tab lists your library playlists; "Add all to queue" works (server-side, one call).
- [ ] Library tab lists saved albums AND songs; album "Add all" works; a library-only song is disabled.
- [ ] No Sonos favorite → "Favorite one Apple Music track…" empty state.
- [ ] Append failure → error banner is visible and credentials re-discover on next launch.
- [ ] Edge cases to watch (see spike note "Known follow-ups"): a user-uploaded library album with no
      catalog counterpart; playlists containing music videos (videos are filtered out).
