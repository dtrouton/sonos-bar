# Apple Music SMAPI Spike Findings — 2026-04-19

## Summary

The original plan assumed SMAPI-via-speaker-proxy would give us Apple Music library browse + catalog search. The spike proved that assumption wrong and simultaneously validated a viable alternative (iTunes Search API + credential extraction from favorites) by running real `AddURIToQueue` calls against a live speaker.

## Service linkage (confirmed)

| Field | Value |
|-------|-------|
| `sid` | `204` |
| `serviceType` | `52231` (= `204 * 256 + 7`) |
| Active-account `sn` (from `ListAvailableServices`) | `5` |
| Auth policy | `AppLink` |
| Apple SMAPI endpoint URL | `https://sonos-music.apple.com/ws/SonosSoap` |
| CDUDN (as constructed from `type * 256`) | `SA_RINCON52231_X_#Svc52231-0-Token` |
| **CDUDN as it actually appears in live favorites** | `SA_RINCON52231_X_#Svc52231-890cb54f-Token` |

The discovered `sn=5` is NOT the `sn` that actually plays — the favorites on this household use `sn=19`, which corresponds to a different (still-linked) Apple Music account slot. **Trust the favorite, not the ListAvailableServices response.**

The `-890cb54f-` segment is a hex per-account token, not a placeholder. The node-sonos-http-api template with `-0-` is stale for modern Apple Music linkages. Using the stale value risks playback failure.

## ContentDirectory: what actually browses (and what doesn't)

Root (`ObjectID=0`) exposes 6 top-level containers:

| ObjectID | Title | Relevant to Apple Music? |
|----------|-------|--------------------------|
| `A:` | Attributes (local music only — SMB shares) | ❌ not Apple Music |
| `S:` | Music Shares (SMB) | ❌ |
| `SQ:` | Saved Queues | ✅ contains Apple Music tracks (user-saved) |
| `R:` | Internet Radio | ❌ |
| `FV:2` | Favorites | ✅ can include Apple Music playlists/albums/tracks |
| `Q:` | Queues | ✅ current queue only |

`A:` drills down into local library containers (`A:ARTIST`, `A:ALBUMARTIST`, `A:ALBUM`, `A:GENRE`, `A:COMPOSER`, `A:TRACKS`, `A:PLAYLISTS`) — none of which reach Apple Music.

`S:` enumerates network music shares. `S://192.168.68.78/music` and `S://DS220j/music` — LAN SMB shares, not music services.

### Probed candidate ObjectIDs (all returned `701 UPnPError` = no such object)

- `SA:204`
- `0fffffff0000`
- `RINCON_949F3E057DE401400#0`
- `0fffffff0music:204`
- `0fffffff0musicsvc204`
- `0fffffff0services`
- `00020000`
- `S:204`
- `S:204:playlists`
- `S:204:albums`
- `S:204:songs`
- `0fffffff0library`

**Conclusion:** `ContentDirectory.Browse` on the speaker does not expose Apple Music library content under any ObjectID pattern. The speaker uses SMAPI internally but does not re-expose it via ContentDirectory for third-party callers.

## MusicServices SOAP service on the speaker

Valid actions we observed:
- `ListAvailableServices` ✅ (returns full service descriptor XML including `Uri`/`SecureUri` for each linked service)
- `GetSessionId(ServiceId, Username)` → returned `806 UPnPError` (invalid argument) with ServiceId=204, Username="". Likely needs a Username tied to the AppLink account, which we can't construct without the real session.

Actions we tried that returned `401 UPnPError` (= no such action):
- `Search(Id, Term, Index, Count)` with various Id values (`tracks`, `albums`, `artists`)

**Conclusion:** `MusicServices.Search` is not a real action on the speaker. "Search" in SMAPI exists, but only on the service's own endpoint (Apple's SMAPI URL) — not on the speaker.

## Apple's SMAPI endpoint (direct)

`https://sonos-music.apple.com/ws/SonosSoap` — confirmed from the descriptor returned by `ListAvailableServices`.

Requests attempted:
- `search(tracks, "taylor swift", 0, 5)` — unauth'd → `SonosError 999` (generic)
- `getMetadata(root, 0, 10)` — unauth'd → `SonosError 999`
- `getAppLink(householdId=Sonos_test, hardware=sonobar, osVersion="macOS 14")` — unauth'd → `SonosError 999`
- Each of the above retried with Sonos-style SOAP credentials header (`<credentials><deviceId>RINCON_...</deviceId><deviceProvider>Sonos</deviceProvider></credentials>`) plus `User-Agent: Linux UPnP/1.0 Sonos/86.6-75110 (ZPS37)` → all returned `SonosError 999`.

The generic 999 code, returned regardless of payload shape, headers, or auth attempt, is the fingerprint of **TLS client certificate verification**: the server rejects the connection (or the request body) before inspecting any SOAP content. Real Sonos speakers present a cert signed by Sonos, and Apple's SMAPI verifies it. We can't produce that cert.

This matches the public svrooij Sonos API docs: *"Sonos locked down communication with most services, by no longer allowing access to the needed access tokens."*

## Favorites content (for this household — illustrative)

7 entries in `FV:2`, 4 of which are Apple Music:

| # | Title | Service | Item type |
|---|-------|---------|-----------|
| 1 | Christmas (minus Wham!) | Apple Music | library playlist (`libraryplaylist%3Ap.gek1Rvzfo14X1`) |
| 2 | Discover Sonos Radio | Sonos Radio | shortcut |
| 3 | Dreaming of Bones | Apple Music | album (`album%3A1649042949`) |
| 4 | Morning Coffee | Apple Music | library playlist (`libraryplaylist%3Ap.gek1RKqCo14X1`) |
| 5 | Puppy Sleeping Music | Apple Music | track (`song%3A1537073461`) |
| 6 | Sonos Presents | Sonos Radio | shortcut |
| 7 | Trending Now | Sonos Radio | shortcut |

Each Apple Music entry embeds a nested DIDL in `<r:resMD>` (HTML-entity-encoded) containing the `<desc id="cdudn">SA_RINCON52231_X_#Svc52231-890cb54f-Token</desc>` we use for playback.

Saved queues (`SQ:`) contains 7 user-created queues; all are `sid=204` Apple Music content. Each entry is a container the speaker can drill into for track listings.

## Playback verification (live speaker)

Three direct-SOAP tests against Play Room (`192.168.68.90`):

### Test 1: Track URI from iTunes Search result

1. `GET https://itunes.apple.com/search?term=bohemian+rhapsody&entity=song&limit=3&country=GB` → `trackId=1422700837` for "Bohemian Rhapsody" by Queen.
2. Constructed URI: `x-sonos-http:song%3a1422700837.mp4?sid=204&flags=8224&sn=19`
3. Constructed DIDL with `<desc>SA_RINCON52231_X_#Svc52231-890cb54f-Token</desc>`.
4. `AVTransport.AddURIToQueue` → **HTTP 200**, response: `<FirstTrackNumberEnqueued>35</FirstTrackNumberEnqueued><NumTracksAdded>1</NumTracksAdded>`.

### Test 2: Album container URI (from existing favorite's album ID)

1. Used album ID `1649042949` (from the "Dreaming of Bones" favorite).
2. URI: `x-rincon-cpcontainer:1004206calbum%3a1649042949` (no query string needed on container URIs).
3. DIDL with same token as Test 1.
4. `AVTransport.AddURIToQueue` → **HTTP 200**, response: `<NumTracksAdded>9</NumTracksAdded>`. Server-side expansion of container → 9 queue entries.

### Test 3: Cleanup

`RemoveTrackFromQueue` iteratively for positions 35–43 → queue returned to pre-test length of 34. Confirmed.

## Design implications

1. **Abandon SMAPI-library-browse path**. The spike closed the door empirically — no amount of follow-up investigation unlocks this without paying for MusicKit.
2. **Adopt iTunes Search API + credential extraction** (the scottwaters/SonosController pattern). iTunes IDs are binary-compatible with the Sonos URI templates we have.
3. **Extract credentials, don't construct them.** The static `-0-` token and the `sn` from `ListAvailableServices` are both wrong for Apple Music playback on modern linkages. Trust the favorite.
4. **Credential-extraction prerequisite: at least one Apple Music favorite.** The user establishes this via the Sonos app; SonoBar cannot create a favorite. Communicated in the tab's empty state copy.
