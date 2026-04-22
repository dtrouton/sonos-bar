import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicURIs Tests")
struct AppleMusicURIsTests {

    private let creds = AppleMusicCredentials(sn: 19, accountToken: "890cb54f")

    @Test("Track URI matches verified spike format")
    func trackURI() {
        // This is the exact URI format that succeeded in the Task 0 spike's
        // AddURIToQueue live-speaker test.
        let uri = AppleMusicURIs.trackURI(id: "1422700837", sn: 19)
        #expect(uri == "x-sonos-http:song%3a1422700837.mp4?sid=204&flags=8224&sn=19")
    }

    @Test("Album container URI uses cpcontainer prefix, no query string")
    func albumURI() {
        // Verified in spike: album container URIs take no sid/sn/flags suffix.
        #expect(AppleMusicURIs.albumContainerURI(id: "1649042949") ==
                "x-rincon-cpcontainer:1004206calbum%3a1649042949")
    }

    @Test("DIDL for track uses extracted account token, not hardcoded 0")
    func didlTrack() {
        let track = AppleMusicTrack(id: "1422700837", title: "Bohemian Rhapsody",
                                    artist: "Queen", album: "Greatest Hits",
                                    albumId: "1422700834",
                                    artworkURL: URL(string: "https://example.com/art.jpg"),
                                    durationSec: 355)
        let didl = AppleMusicURIs.didl(for: .track(track), credentials: creds)
        #expect(didl.contains("object.item.audioItem.musicTrack"))
        #expect(didl.contains("SA_RINCON52231_X_#Svc52231-890cb54f-Token"))
        #expect(!didl.contains("-0-Token"))
        #expect(didl.contains("<dc:title>Bohemian Rhapsody</dc:title>"))
    }

    @Test("DIDL escapes special XML characters in title")
    func didlEscapesTitle() {
        let track = AppleMusicTrack(id: "1", title: "Rock & Roll",
                                    artist: nil, album: nil, albumId: nil,
                                    artworkURL: nil, durationSec: nil)
        let didl = AppleMusicURIs.didl(for: .track(track), credentials: creds)
        #expect(didl.contains("Rock &amp; Roll"))
        #expect(!didl.contains("Rock & Roll</dc:title>"))
    }

    @Test("DIDL for album uses container class")
    func didlAlbum() {
        let album = AppleMusicAlbum(id: "1649042949", title: "Dreaming of Bones",
                                    artist: nil, artworkURL: nil, trackCount: 9)
        let didl = AppleMusicURIs.didl(for: .album(album), credentials: creds)
        #expect(didl.contains("object.container.album.musicAlbum"))
        #expect(didl.contains("890cb54f"))
    }

    @Test("Different credentials produce different DIDL tokens")
    func differentCreds() {
        let track = AppleMusicTrack(id: "1", title: "X", artist: nil, album: nil,
                                    albumId: nil, artworkURL: nil, durationSec: nil)
        let a = AppleMusicURIs.didl(for: .track(track),
                                    credentials: AppleMusicCredentials(sn: 19, accountToken: "aaaaaaaa"))
        let b = AppleMusicURIs.didl(for: .track(track),
                                    credentials: AppleMusicCredentials(sn: 19, accountToken: "bbbbbbbb"))
        #expect(a.contains("aaaaaaaa"))
        #expect(b.contains("bbbbbbbb"))
        #expect(a != b)
    }
}
