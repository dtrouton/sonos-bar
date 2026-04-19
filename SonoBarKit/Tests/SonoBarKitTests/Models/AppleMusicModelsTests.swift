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
}
