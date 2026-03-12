import Testing
@testable import SonoBarKit

@Suite("ContentItem Tests")
struct ContentItemTests {

    @Test func testContentItemCreation() {
        let item = ContentItem(
            id: "FV:2/3",
            title: "My Playlist",
            albumArtURI: "/getaa?uri=x-sonosapi-hls-static",
            resourceURI: "x-rincon-cpcontainer:FV:2/3",
            rawDIDL: "<DIDL-Lite/>",
            itemClass: "object.container.playlistContainer",
            description: "12 tracks"
        )
        #expect(item.id == "FV:2/3")
        #expect(item.title == "My Playlist")
        #expect(item.isContainer == true)
    }

    @Test func testAudioItemIsNotContainer() {
        let item = ContentItem(
            id: "Q:0/1",
            title: "Song",
            resourceURI: "x-file-cifs://server/song.mp3",
            rawDIDL: "<DIDL-Lite/>",
            itemClass: "object.item.audioItem.musicTrack",
            description: "Artist"
        )
        #expect(item.isContainer == false)
    }
}
