import Foundation
import Testing
@testable import SonoBarKit

@Suite("Plex Model Tests")
struct PlexModelsTests {

    @Test func testPlexLibraryParsesFromJSON() throws {
        let json = """
        {"key":"5","title":"Audiobooks","type":"artist"}
        """.data(using: .utf8)!

        let library = try JSONDecoder().decode(PlexLibrary.self, from: json)
        #expect(library.id == "5")
        #expect(library.title == "Audiobooks")
        #expect(library.type == "artist")
    }

    @Test func testPlexAlbumParsesFromJSON() throws {
        let json = """
        {
            "ratingKey": "12345",
            "title": "Abbey Road",
            "parentTitle": "The Beatles",
            "thumb": "/library/metadata/12345/thumb/1609459200",
            "leafCount": 17,
            "year": 1969,
            "viewOffset": 180000
        }
        """.data(using: .utf8)!

        let album = try JSONDecoder().decode(PlexAlbum.self, from: json)
        #expect(album.id == "12345")
        #expect(album.title == "Abbey Road")
        #expect(album.artist == "The Beatles")
        #expect(album.thumbPath == "/library/metadata/12345/thumb/1609459200")
        #expect(album.trackCount == 17)
        #expect(album.year == 1969)
        #expect(album.viewOffset == 180000)
    }

    @Test func testPlexTrackParsesFromJSON() throws {
        let json = """
        {
            "ratingKey": "67890",
            "title": "Come Together",
            "parentTitle": "Abbey Road",
            "grandparentTitle": "The Beatles",
            "duration": 259000,
            "viewOffset": 45000,
            "index": 1,
            "thumb": "/library/metadata/67890/thumb/1609459200",
            "lastViewedAt": 1609459200,
            "Media": [
                {
                    "Part": [
                        {
                            "key": "/library/parts/67890/1609459200/file.mp3"
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let track = try JSONDecoder().decode(PlexTrack.self, from: json)
        #expect(track.id == "67890")
        #expect(track.title == "Come Together")
        #expect(track.albumTitle == "Abbey Road")
        #expect(track.artistName == "The Beatles")
        #expect(track.duration == 259000)
        #expect(track.viewOffset == 45000)
        #expect(track.index == 1)
        #expect(track.partKey == "/library/parts/67890/1609459200/file.mp3")
        #expect(track.thumbPath == "/library/metadata/67890/thumb/1609459200")
        #expect(track.lastViewedAt == Date(timeIntervalSince1970: 1609459200))
    }

    @Test func testPlexResponseWrapsItems() throws {
        let json = """
        {
            "MediaContainer": {
                "size": 2,
                "Directory": [
                    {"key": "1", "title": "Music", "type": "artist"},
                    {"key": "2", "title": "Audiobooks", "type": "artist"}
                ]
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PlexResponse<PlexLibrary>.self, from: json)
        #expect(response.mediaContainer.size == 2)
        let items = response.mediaContainer.items
        #expect(items.count == 2)
        #expect(items[0].title == "Music")
        #expect(items[1].title == "Audiobooks")
    }

    @Test func testPlexTrackHandlesMissingOptionals() throws {
        let json = """
        {
            "ratingKey": "99999",
            "title": "Unknown Track",
            "parentTitle": "Unknown Album",
            "grandparentTitle": "Unknown Artist",
            "duration": 120000,
            "index": 5,
            "Media": [
                {
                    "Part": [
                        {
                            "key": "/library/parts/99999/file.flac"
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let track = try JSONDecoder().decode(PlexTrack.self, from: json)
        #expect(track.id == "99999")
        #expect(track.title == "Unknown Track")
        #expect(track.thumbPath == nil)
        #expect(track.lastViewedAt == nil)
        #expect(track.viewOffset == 0)
    }
}
