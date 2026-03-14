import Testing
import Foundation
@testable import SonoBarKit

@Suite("PlexClient Tests")
struct PlexClientTests {

    // MARK: - Test JSON Fixtures

    private static let librariesJSON = """
    {
        "MediaContainer": {
            "size": 2,
            "Directory": [
                { "key": "1", "title": "Music", "type": "artist" },
                { "key": "2", "title": "Audiobooks", "type": "artist" }
            ]
        }
    }
    """.data(using: .utf8)!

    private static let albumsJSON = """
    {
        "MediaContainer": {
            "size": 1,
            "Metadata": [
                {
                    "ratingKey": "100",
                    "title": "Abbey Road",
                    "parentTitle": "The Beatles",
                    "thumb": "/library/metadata/100/thumb/12345",
                    "leafCount": 17,
                    "year": 1969
                }
            ]
        }
    }
    """.data(using: .utf8)!

    private static let tracksJSON = """
    {
        "MediaContainer": {
            "size": 1,
            "Metadata": [
                {
                    "ratingKey": "200",
                    "title": "Come Together",
                    "parentTitle": "Abbey Road",
                    "grandparentTitle": "The Beatles",
                    "duration": 259000,
                    "viewOffset": 0,
                    "index": 1,
                    "thumb": "/library/metadata/100/thumb/12345",
                    "Media": [
                        {
                            "Part": [
                                { "key": "/library/parts/200/file.mp3" }
                            ]
                        }
                    ]
                }
            ]
        }
    }
    """.data(using: .utf8)!

    // MARK: - Test: getLibraries parses response

    @Test func testGetLibrariesParsesResponse() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.librariesJSON
        let client = PlexClient(host: "192.168.1.50", token: "test-token", httpClient: mock)

        let libraries = try await client.getLibraries()

        #expect(libraries.count == 2)
        #expect(libraries[0].id == "1")
        #expect(libraries[0].title == "Music")
        #expect(libraries[0].type == "artist")
        #expect(libraries[1].id == "2")
        #expect(libraries[1].title == "Audiobooks")
    }

    // MARK: - Test: getLibraries sends token header

    @Test func testGetLibrariesSendsTokenHeader() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.librariesJSON
        let client = PlexClient(host: "192.168.1.50", token: "my-secret-token", httpClient: mock)

        _ = try await client.getLibraries()

        let request = try #require(mock.lastRequest)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "my-secret-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    // MARK: - Test: getAlbums uses correct path

    @Test func testGetAlbumsUsesCorrectPath() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.albumsJSON
        let client = PlexClient(host: "192.168.1.50", token: "test-token", httpClient: mock)

        let albums = try await client.getAlbums(sectionId: "3")

        let request = try #require(mock.lastRequest)
        let url = try #require(request.url)
        #expect(url.path == "/library/sections/3/all")
        // Verify type=9 query parameter
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let typeParam = components.queryItems?.first(where: { $0.name == "type" })
        #expect(typeParam?.value == "9")
        // Verify parsed album
        #expect(albums.count == 1)
        #expect(albums[0].title == "Abbey Road")
        #expect(albums[0].artist == "The Beatles")
    }

    // MARK: - Test: getTracks uses correct path

    @Test func testGetTracksUsesCorrectPath() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.tracksJSON
        let client = PlexClient(host: "192.168.1.50", token: "test-token", httpClient: mock)

        let tracks = try await client.getTracks(albumId: "100")

        let request = try #require(mock.lastRequest)
        let url = try #require(request.url)
        #expect(url.path == "/library/metadata/100/children")
        #expect(tracks.count == 1)
        #expect(tracks[0].title == "Come Together")
        #expect(tracks[0].partKey == "/library/parts/200/file.mp3")
    }

    // MARK: - Test: audioURL constructs correctly

    @Test func testAudioURLConstructsCorrectly() async throws {
        let client = PlexClient(host: "192.168.1.50", port: 32400, token: "abc123", httpClient: CapturingHTTPClient())

        let url = try #require(client.audioURL(partKey: "/library/parts/200/file.mp3"))

        #expect(url.host == "192.168.1.50")
        #expect(url.port == 32400)
        #expect(url.path == "/library/parts/200/file.mp3")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let tokenParam = components.queryItems?.first(where: { $0.name == "X-Plex-Token" })
        #expect(tokenParam?.value == "abc123")
    }

    // MARK: - Test: thumbURL constructs correctly

    @Test func testThumbURLConstructsCorrectly() async throws {
        let client = PlexClient(host: "192.168.1.50", port: 32400, token: "abc123", httpClient: CapturingHTTPClient())

        let url = try #require(client.thumbURL(path: "/library/metadata/100/thumb/12345"))

        #expect(url.host == "192.168.1.50")
        #expect(url.port == 32400)
        #expect(url.path == "/library/metadata/100/thumb/12345")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let tokenParam = components.queryItems?.first(where: { $0.name == "X-Plex-Token" })
        #expect(tokenParam?.value == "abc123")
    }

    // MARK: - Test: 401 throws PlexError.unauthorized

    @Test func testUnauthorizedThrowsPlexError() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Data("Unauthorized".utf8)
        mock.responseStatusCode = 401
        let client = PlexClient(host: "192.168.1.50", token: "bad-token", httpClient: mock)

        await #expect(throws: PlexError.unauthorized) {
            _ = try await client.getLibraries()
        }
    }
}
