import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicLibraryAPIParser Tests")
struct AppleMusicLibraryAPIParserTests {

    // Shapes captured verbatim from /v1/me/library/playlists on a live account.
    private static let playlistsJSON = """
    {"data":[
      {"id":"p.4Y0Jgedf2dPMMBZ","attributes":{"name":"Stories",
        "playParams":{"kind":"playlist","globalId":"pl.u-kv9l2M5C7PK66p8","id":"p.4Y0Jgedf2dPMMBZ","isLibrary":1},
        "artwork":{"width":600,"height":600,"url":"https://is1-ssl.mzstatic.com/image/thumb/gen/{w}x{h}AM.PDCXS11.jpg?t=abc"}}},
      {"id":"p.RB1A8MAu1WbvvP8","attributes":{"name":"Before",
        "playParams":{"isLibrary":1,"kind":"playlist","id":"p.RB1A8MAu1WbvvP8"},
        "artwork":{"width":1200,"height":1200,"url":"https://store-033.blobstore.apple.com/x/image?X-Amz-Signature=deadbeef"}}}
    ]}
    """

    @Test("Mirrored playlist uses globalId + catalog form (isLibrary false)")
    func mirroredPlaylist() {
        let r = AppleMusicLibraryAPIParser.playlists(from: Data(Self.playlistsJSON.utf8))
        let stories = r.first { $0.name == "Stories" }
        #expect(stories?.id == "pl.u-kv9l2M5C7PK66p8")
        #expect(stories?.isLibrary == false)
        #expect(stories?.artworkURL?.absoluteString.contains("600x600") == true)  // {w}x{h} resolved
    }

    @Test("Un-mirrored playlist uses p.xxx library id + library form, keeps custom https art")
    func unmirroredPlaylist() {
        let r = AppleMusicLibraryAPIParser.playlists(from: Data(Self.playlistsJSON.utf8))
        let before = r.first { $0.name == "Before" }
        #expect(before?.id == "p.RB1A8MAu1WbvvP8")
        #expect(before?.isLibrary == true)
        #expect(before?.artworkURL?.absoluteString.hasPrefix("https://store-033.blobstore.apple.com") == true)
    }

    @Test("Track resolves catalog id from playParams; uploaded track keeps library id")
    func tracks() {
        let json = """
        {"data":[
          {"id":"i.matched","attributes":{"name":"Matched","artistName":"A","albumName":"Al",
            "durationInMillis":183000,"playParams":{"id":"i.matched","catalogId":"1422700837","isLibrary":1}}},
          {"id":"i.uploaded","attributes":{"name":"Uploaded","artistName":"B",
            "playParams":{"id":"i.uploaded","isLibrary":1}}}
        ]}
        """
        let r = AppleMusicLibraryAPIParser.tracks(from: Data(json.utf8))
        #expect(r.count == 2)
        #expect(r[0].id == "1422700837")      // catalog id → numeric → playable
        #expect(r[0].durationSec == 183)
        #expect(r[1].id == "i.uploaded")      // no catalog id → library id → disabled in UI
    }

    @Test("Empty/malformed payloads yield empty arrays")
    func emptyAndMalformed() {
        #expect(AppleMusicLibraryAPIParser.playlists(from: Data("{}".utf8)).isEmpty)
        #expect(AppleMusicLibraryAPIParser.tracks(from: Data("not json".utf8)).isEmpty)
    }
}
