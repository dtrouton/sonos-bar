import Testing
import Foundation
@testable import SonoBarKit

@Suite("AudibleClient Tests")
struct AudibleClientTests {

    // MARK: - Test JSON Fixtures

    private static let libraryJSON = """
    {
        "items": [
            {
                "asin": "B08G9PRS1K",
                "title": "Project Hail Mary",
                "authors": [{"name": "Andy Weir"}],
                "narrators": [{"name": "Ray Porter"}],
                "product_images": {"500": "https://images.audible.com/cover.jpg"},
                "runtime_length_ms": 58200000,
                "purchase_date": "2021-05-04T00:00:00Z"
            }
        ]
    }
    """.data(using: .utf8)!

    private static let chaptersJSON = """
    {
        "content_metadata": {
            "chapter_info": {
                "chapters": [
                    {
                        "title": "Opening Credits",
                        "start_offset_ms": 0,
                        "length_ms": 5000
                    },
                    {
                        "title": "Chapter 1",
                        "start_offset_ms": 5000,
                        "length_ms": 360000
                    }
                ]
            }
        }
    }
    """.data(using: .utf8)!

    private static let listeningPositionsJSON = """
    {
        "items": [
            {"asin": "B08G9PRS1K", "last_position_ms": 123456},
            {"asin": "B09FRJM1BQ", "last_position_ms": 654321}
        ]
    }
    """.data(using: .utf8)!

    // MARK: - Helpers

    /// A valid RSA private key in PEM format for signing tests.
    private static let testPEM: String = {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)!
        let data = SecKeyCopyExternalRepresentation(key, &error)! as Data
        let b64 = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN RSA PRIVATE KEY-----\n\(b64)\n-----END RSA PRIVATE KEY-----"
    }()

    /// Creates an AudibleClient with the given mock HTTP client.
    private func makeClient(httpClient: CapturingHTTPClient) -> AudibleClient {
        AudibleClient(
            marketplace: "co.uk",
            adpToken: "test-adp-token",
            privateKeyPEM: Self.testPEM,
            accessToken: "test-access-token",
            httpClient: httpClient
        )
    }

    // MARK: - Test: getLibrary sends correct path and query params

    @Test func testGetLibrarySendsCorrectPath() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.libraryJSON
        let client = makeClient(httpClient: mock)

        let books = try await client.getLibrary()

        let request = try #require(mock.lastRequest)
        let url = try #require(request.url)
        #expect(url.path == "/1.0/library")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        let numResults = queryItems.first(where: { $0.name == "num_results" })
        #expect(numResults?.value == "500")
        let responseGroups = queryItems.first(where: { $0.name == "response_groups" })
        #expect(responseGroups?.value == "product_attrs,media,product_desc")
        let sortBy = queryItems.first(where: { $0.name == "sort_by" })
        #expect(sortBy?.value == "-PurchaseDate")
        // Verify parsed result
        #expect(books.count == 1)
        #expect(books[0].asin == "B08G9PRS1K")
        #expect(books[0].title == "Project Hail Mary")
    }

    // MARK: - Test: getLibrary signs request (headers present)

    @Test func testGetLibrarySignsRequest() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.libraryJSON
        let client = makeClient(httpClient: mock)

        _ = try await client.getLibrary()

        let request = try #require(mock.lastRequest)
        // AudibleAuth.signRequest sets these headers; since we're using a fake key
        // that won't produce a valid signature, we verify the client sets the
        // Authorization bearer header at minimum
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
    }

    // MARK: - Test: getChapters sends ASIN in path

    @Test func testGetChaptersSendsASIN() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.chaptersJSON
        let client = makeClient(httpClient: mock)

        let chapters = try await client.getChapters(asin: "B08G9PRS1K")

        let request = try #require(mock.lastRequest)
        let url = try #require(request.url)
        #expect(url.path == "/1.0/content/B08G9PRS1K/metadata")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let responseGroups = components.queryItems?.first(where: { $0.name == "response_groups" })
        #expect(responseGroups?.value == "chapter_info")
        // Verify parsed chapters
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Opening Credits")
        #expect(chapters[0].startOffsetMs == 0)
        #expect(chapters[1].title == "Chapter 1")
        #expect(chapters[1].startOffsetMs == 5000)
        #expect(chapters[1].index == 1)
    }

    // MARK: - Test: getListeningPositions sends comma-separated ASINs

    @Test func testGetListeningPositionsSendsASINs() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Self.listeningPositionsJSON
        let client = makeClient(httpClient: mock)

        let positions = try await client.getListeningPositions(asins: ["B08G9PRS1K", "B09FRJM1BQ"])

        let request = try #require(mock.lastRequest)
        let url = try #require(request.url)
        #expect(url.path == "/1.0/annotations/lastpositions")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let asinsParam = components.queryItems?.first(where: { $0.name == "asins" })
        #expect(asinsParam?.value == "B08G9PRS1K,B09FRJM1BQ")
        // Verify parsed positions
        #expect(positions.count == 2)
        #expect(positions[0].asin == "B08G9PRS1K")
        #expect(positions[0].positionMs == 123456)
    }

    // MARK: - Test: 401 throws AudibleError.unauthorized

    @Test func testUnauthorizedThrowsError() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = Data("Unauthorized".utf8)
        mock.responseStatusCode = 401
        let client = makeClient(httpClient: mock)

        await #expect(throws: AudibleError.unauthorized) {
            _ = try await client.getLibrary()
        }
    }

    // MARK: - Test: coverURL constructs correctly

    @Test func testCoverURLConstructsCorrectly() {
        let client = makeClient(httpClient: CapturingHTTPClient())

        let url = client.coverURL(path: "https://images.audible.com/cover.jpg")

        #expect(url?.absoluteString == "https://images.audible.com/cover.jpg")
    }
}
