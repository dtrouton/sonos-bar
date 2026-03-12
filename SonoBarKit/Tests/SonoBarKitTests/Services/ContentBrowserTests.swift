import Testing
@testable import SonoBarKit

@Suite("ContentBrowser Tests")
struct ContentBrowserTests {

    // Helper: wraps DIDL-Lite in a Browse response envelope
    private func makeBrowseResponse(didl: String) -> Data {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
        <Result>\(didl.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</Result>
        <NumberReturned>1</NumberReturned>
        <TotalMatches>1</TotalMatches>
        </u:BrowseResponse>
        </s:Body>
        </s:Envelope>
        """
        return Data(xml.utf8)
    }

    @Test func testBrowseFavoritesSendsCorrectObjectID() async throws {
        let mock = CapturingHTTPClient()
        let didl = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        <item id="FV:2/1" parentID="FV:2" restricted="true">
        <dc:title>My Fav</dc:title>
        <upnp:class>object.item.audioItem</upnp:class>
        <res>x-sonosapi-stream:s123</res>
        </item>
        </DIDL-Lite>
        """
        mock.responseData = makeBrowseResponse(didl: didl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let items = try await ContentBrowser.browseFavorites(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<ObjectID>FV:2</ObjectID>"))
        #expect(body.contains("<BrowseFlag>BrowseDirectChildren</BrowseFlag>"))
        #expect(items.count == 1)
        #expect(items[0].title == "My Fav")
    }

    @Test func testBrowsePlaylistsSendsCorrectObjectID() async throws {
        let mock = CapturingHTTPClient()
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"></DIDL-Lite>
        """
        mock.responseData = makeBrowseResponse(didl: didl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        _ = try await ContentBrowser.browsePlaylists(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<ObjectID>SQ:</ObjectID>"))
    }

    @Test func testBrowseQueueSendsCorrectObjectID() async throws {
        let mock = CapturingHTTPClient()
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"></DIDL-Lite>
        """
        mock.responseData = makeBrowseResponse(didl: didl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        _ = try await ContentBrowser.browseQueue(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<ObjectID>Q:0</ObjectID>"))
    }

    @Test func testPlayItemSendsSetAVTransportURI() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "SetAVTransportURI", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let item = ContentItem(
            id: "FV:2/3",
            title: "Test",
            resourceURI: "x-sonosapi-stream:s123",
            rawDIDL: "<item><dc:title>Test</dc:title></item>",
            itemClass: "object.item.audioItem"
        )

        try await ContentBrowser.playItem(client: client, item: item)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:Play") || body.contains("<u:SetAVTransportURI"))
    }
}
