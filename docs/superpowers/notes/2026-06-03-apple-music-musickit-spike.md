# Apple Music MusicKit Spike Findings — 2026-06-03

Task 0 of the MusicKit re-architecture. Run via direct SOAP against the live "Play Room"
speaker (`192.168.68.90:1400`) from the dev machine (`192.168.68.97`, same /22 subnet).
SSDP multicast discovery was blocked in the shell sandbox, but direct unicast HTTP to the
speaker works fine.

## Q1 — Can a CONSTRUCTED library-playlist URI play? → **YES**

The decisive question (library-playlist playback was never verified; only catalog
track/album were in the 2026-04-19 spike).

**Test:** Built a fresh container URI + DIDL for library playlist `p.gek1Rvzfo14X1`
("Christmas (minus Wham!)") from scratch — i.e. using only the playlist id the way
MusicKit would surface it, NOT replaying the favorite's stored `res` — and called
`AddURIToQueue`.

Exact values that worked (this is the plan's `AppleMusicURIs` output format, unchanged):

- URI: `x-rincon-cpcontainer:1006206clibraryplaylist%3ap.gek1Rvzfo14X1`
  (lowercase `%3a`, **no `?sid/flags/sn` query string**)
- DIDL `<item>` id: `1006206clibraryplaylist%3ap.gek1Rvzfo14X1`
- DIDL `<item>` parentID: `00020000playlist:`
- `<upnp:class>`: `object.container.playlistContainer`
- `<desc id="cdudn" …>`: `SA_RINCON52231_X_#Svc52231-890cb54f-Token`

**Result:** `HTTP 200`, `NumTracksAdded=83`, `FirstTrackNumberEnqueued=35`. Cleaned up
immediately with `RemoveTrackRangeFromQueue(start=35, count=83)` → `HTTP 200`. Live
playback was never touched (no `Play` call).

**Implication:** Use the **server-side** playlist append in Task 7 (one `AddURIToQueue`
call; Sonos expands the container). Task 6's `playlistContainerURI` format is correct as
written. The earlier note that container URIs need no query string (from the album test)
holds for playlists too. The plan's `parentID=00020000playlist:` guess works — no need to
mirror the favorite's id-as-parentID.

## Q2 — Library song → playable catalog id

Catalog-track URI playback is already proven (2026-04-19 spike Test 1, and the
"Puppy Sleeping Music" song favorite here is `x-sonos-http:song%3A1537073461.mp4?sid=204&flags=8232&sn=19`).
The MusicKit-side resolution of a library song's `playParameters` → catalog id is pure
logic, unit-tested in `AppleMusicCatalogIDResolverTests`. Whether a *specific* library
song yields a working catalog id is a runtime/MusicKit property covered by manual QA
(Task 11). No shell-testable surface; nothing blocks the build.

## Favorites observed (reference — household `192.168.68.90`)

| Title | Kind | Container/track id | sn | token |
|-------|------|--------------------|----|-------|
| Christmas (minus Wham!) | library playlist | `1006206clibraryplaylist%3Ap.gek1Rvzfo14X1` | 19 | `890cb54f` |
| Morning Coffee | library playlist | `1006206clibraryplaylist%3Ap.gek1RKqCo14X1` | 19 | `890cb54f` |
| ’90s Hits Essentials | catalog playlist | `1006206cplaylist%3Apl.0d70b7c9…` | 19 | `890cb54f` |
| ’90s Club Essentials | catalog playlist | `1006206cplaylist%3Apl.310497207…` | **20** | **`9ae37e1a`** |
| Dreaming of Bones | album | `1004206calbum%3A1649042949` | 19 | `890cb54f` |
| Puppy Sleeping Music | track | `song%3A1537073461` | 19 | `890cb54f` |

### Multi-account note

One catalog playlist favorite resolves to a **second** Apple Music account slot
(`sn=20`, token `9ae37e1a`) while the rest use `sn=19`/`890cb54f`. Catalog content plays
regardless of which linked slot authorizes, so the app's single-credential model (extract
the first `sid=204` favorite → `sn=19`/`890cb54f`) is fine for catalog search and catalog
playlists. **Library** items are account-specific: if the Sonos-linked account whose token
we extract differs from the MusicKit-signed-in account, that account's library playlists
won't authorize. Edge case for manual QA; not a V1 blocker.

## Decision carried into implementation

**Q1 SUCCESS branch is active:**
- Task 2 Step 4: ADD the `.playlist` case to `AppleMusicPlayable` (no longer deferred).
- Task 6: IMPLEMENT `playlistContainerURI` + `.playlist` DIDL (format above, verified).
- Task 7: server-side `appendAppleMusicPlaylist` via `AppleMusicURIs.playlistContainerURI`.
