import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicModels Tests")
struct AppleMusicModelsTests {

    @Test("Track has expected properties")
    func trackShape() {
        let t = AppleMusicTrack(
            id: "1422700837",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "Greatest Hits",
            albumId: "1422700834",
            artworkURL: URL(string: "https://example.com/600x600bb.jpg"),
            durationSec: 355
        )
        #expect(t.id == "1422700837")
        #expect(t.albumId == "1422700834")
    }

    @Test("Album has expected properties")
    func albumShape() {
        let a = AppleMusicAlbum(
            id: "1649042949",
            title: "Dreaming of Bones",
            artist: "Someone",
            artworkURL: nil,
            trackCount: 9
        )
        #expect(a.trackCount == 9)
    }

    @Test("Artist has expected properties")
    func artistShape() {
        let a = AppleMusicArtist(id: "909253", name: "Jack Johnson")
        #expect(a.name == "Jack Johnson")
    }

    @Test("Credentials equality works")
    func credentialsEquality() {
        let a = AppleMusicCredentials(sn: 19, accountToken: "890cb54f")
        let b = AppleMusicCredentials(sn: 19, accountToken: "890cb54f")
        let c = AppleMusicCredentials(sn: 20, accountToken: "890cb54f")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Error equality")
    func errorEquality() {
        #expect(AppleMusicError.notLinked == AppleMusicError.notLinked)
        #expect(AppleMusicError.httpError(500) != AppleMusicError.httpError(404))
    }

    // MARK: - AppleMusicPlayable accessors

    @Test("Playable.track forwards id/title/artworkURL from the wrapped Track")
    func playableTrackForwards() {
        let artwork = URL(string: "https://example.com/t.jpg")
        let track = AppleMusicTrack(
            id: "t1", title: "Track Title", artist: "A", album: "Alb",
            albumId: "al1", artworkURL: artwork, durationSec: 100
        )
        let p = AppleMusicPlayable.track(track)
        #expect(p.id == "t1")
        #expect(p.title == "Track Title")
        #expect(p.artworkURL == artwork)
    }

    @Test("Playable.album forwards id/title/artworkURL from the wrapped Album")
    func playableAlbumForwards() {
        let artwork = URL(string: "https://example.com/a.jpg")
        let album = AppleMusicAlbum(
            id: "a1", title: "Album Title", artist: "A", artworkURL: artwork, trackCount: 12
        )
        let p = AppleMusicPlayable.album(album)
        #expect(p.id == "a1")
        #expect(p.title == "Album Title")
        #expect(p.artworkURL == artwork)
    }

    @Test("Playable.track exposes nil artwork when the track has none")
    func playableNilArtwork() {
        let track = AppleMusicTrack(
            id: "t2", title: "No Art", artist: nil, album: nil,
            albumId: nil, artworkURL: nil, durationSec: nil
        )
        #expect(AppleMusicPlayable.track(track).artworkURL == nil)
    }
}
