import Testing
import Foundation
@testable import SonoBarKit

@Suite("ITunesSearchClient Tests")
struct ITunesSearchClientTests {

    /// iTunes returns separate responses per entity; stub per-entity responses.
    final class SwitchingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
        var responses: [String: Data] = [:]
        var statusCode: Int = 200

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let entity = comps.queryItems?.first(where: { $0.name == "entity" })?.value ?? ""
            let body = responses[entity] ?? Data("{\"resultCount\":0,\"results\":[]}".utf8)
            let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            return (body, response)
        }
    }

    private static let songJSON = """
    {"resultCount":1,"results":[{
      "wrapperType":"track","kind":"song",
      "trackId":1422700837,
      "artistId":3296287,
      "collectionId":1422700834,
      "artistName":"Queen","collectionName":"Greatest Hits","trackName":"Bohemian Rhapsody",
      "artworkUrl100":"https://example.com/100x100bb.jpg",
      "trackTimeMillis":354947
    }]}
    """.data(using: .utf8)!

    private static let albumJSON = """
    {"resultCount":1,"results":[{
      "wrapperType":"collection","collectionType":"Album",
      "collectionId":1422700834,"artistId":3296287,
      "collectionName":"Greatest Hits","artistName":"Queen",
      "artworkUrl100":"https://example.com/100x100bb.jpg",
      "trackCount":17
    }]}
    """.data(using: .utf8)!

    private static let artistJSON = """
    {"resultCount":1,"results":[{
      "wrapperType":"artist","artistType":"Artist",
      "artistId":3296287,"artistName":"Queen"
    }]}
    """.data(using: .utf8)!

    @Test("Search merges tracks, albums, and artists")
    func search() async throws {
        let mock = SwitchingHTTPClient()
        mock.responses["song"] = Self.songJSON
        mock.responses["album"] = Self.albumJSON
        mock.responses["musicArtist"] = Self.artistJSON
        let client = ITunesSearchClient(country: "GB", httpClient: mock)

        let r = try await client.search("queen")
        #expect(r.tracks.count == 1)
        #expect(r.tracks[0].id == "1422700837")
        #expect(r.tracks[0].title == "Bohemian Rhapsody")
        #expect(r.tracks[0].durationSec == 354)
        #expect(r.albums.count == 1)
        #expect(r.albums[0].id == "1422700834")
        #expect(r.artists.count == 1)
        #expect(r.artists[0].id == "3296287")
        #expect(r.artists[0].name == "Queen")
    }

    @Test("Artwork URL upsized from 100x100 to 600x600")
    func artworkUpsize() async throws {
        let mock = SwitchingHTTPClient()
        mock.responses["song"] = Self.songJSON
        let client = ITunesSearchClient(country: "US", httpClient: mock)
        let r = try await client.search("x")
        #expect(r.tracks[0].artworkURL?.absoluteString.contains("600x600bb.jpg") == true)
    }

    @Test("HTTP error maps to httpError(code)")
    func httpError() async {
        let mock = SwitchingHTTPClient()
        mock.statusCode = 500
        let client = ITunesSearchClient(country: "US", httpClient: mock)
        await #expect(throws: AppleMusicError.self) {
            _ = try await client.search("queen")
        }
    }

    @Test("Malformed JSON maps to invalidResponse")
    func malformed() async {
        let mock = SwitchingHTTPClient()
        mock.responses["song"] = Data("not json".utf8)
        let client = ITunesSearchClient(country: "US", httpClient: mock)
        await #expect(throws: AppleMusicError.invalidResponse) {
            _ = try await client.search("queen")
        }
    }
}
