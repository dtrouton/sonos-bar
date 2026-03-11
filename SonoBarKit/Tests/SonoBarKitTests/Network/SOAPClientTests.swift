import Testing
@testable import SonoBarKit

// MARK: - MockHTTPClient

final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    var lastSnapshot: URLRequestSnapshot?
    var responseData: Data = Data()
    var responseStatusCode: Int = 200
    var shouldThrow: (any Error)?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastSnapshot = URLRequestSnapshot(request)
        if let error = shouldThrow {
            throw error
        }
        let url = request.url ?? URL(string: "http://localhost")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (responseData, response)
    }
}

@Suite("SOAPClient Tests")
struct SOAPClientTests {

    @Test func testCallActionBuildsCorrectRequest() async throws {
        let mock = MockHTTPClient()
        let responseXML = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <CurrentVolume>42</CurrentVolume>
        </u:GetVolumeResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(responseXML.utf8)

        let client = SOAPClient(host: "192.168.1.100", port: 1400, httpClient: mock)
        let result = try await client.callAction(
            service: .renderingControl,
            action: "GetVolume",
            params: ["InstanceID": "0", "Channel": "Master"]
        )

        let snapshot = try #require(mock.lastSnapshot)
        #expect(snapshot.urlString == "http://192.168.1.100:1400/MediaRenderer/RenderingControl/Control")
        #expect(snapshot.method == "POST")
        #expect(snapshot.contentType == "text/xml; charset=utf-8")
        #expect(snapshot.soapAction == "\"urn:schemas-upnp-org:service:RenderingControl:1#GetVolume\"")
        #expect(snapshot.timeout == 5)

        let bodyString = try #require(snapshot.bodyString)
        #expect(bodyString.contains("<u:GetVolume"))
        #expect(bodyString.contains("<InstanceID>0</InstanceID>"))

        #expect(result["CurrentVolume"] == "42")
    }

    @Test func testCallActionTupleOverload() async throws {
        let mock = MockHTTPClient()
        let responseXML = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:PlayResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        </u:PlayResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(responseXML.utf8)

        let client = SOAPClient(host: "192.168.1.100", port: 1400, httpClient: mock)
        _ = try await client.callAction(
            service: .avTransport,
            action: "Play",
            params: [("InstanceID", "0"), ("Speed", "1")]
        )

        let snapshot = try #require(mock.lastSnapshot)
        #expect(snapshot.urlString == "http://192.168.1.100:1400/MediaRenderer/AVTransport/Control")
        #expect(snapshot.soapAction == "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")

        let bodyString = try #require(snapshot.bodyString)
        #expect(bodyString.contains("<u:Play"))
        #expect(bodyString.contains("<InstanceID>0</InstanceID>"))
        #expect(bodyString.contains("<Speed>1</Speed>"))
    }

    @Test func testCallActionThrowsOnSOAPFault() async throws {
        let mock = MockHTTPClient()
        let faultXML = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <s:Fault>
          <faultcode>s:Client</faultcode>
          <faultstring>UPnPError</faultstring>
          <detail><UPnPError><errorCode>701</errorCode></UPnPError></detail>
        </s:Fault>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(faultXML.utf8)

        let client = SOAPClient(host: "192.168.1.100", port: 1400, httpClient: mock)

        do {
            _ = try await client.callAction(
                service: .avTransport,
                action: "Play",
                params: ["InstanceID": "0", "Speed": "1"]
            )
            Issue.record("Expected SOAPError to be thrown")
        } catch let error as SOAPError {
            #expect(error.code == 701)
        } catch {
            Issue.record("Expected SOAPError, got \(error)")
        }
    }

    @Test func testDefaultPort() async throws {
        let mock = MockHTTPClient()
        let responseXML = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:PlayResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        </u:PlayResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(responseXML.utf8)

        let client = SOAPClient(host: "192.168.1.50", httpClient: mock)
        _ = try await client.callAction(
            service: .avTransport,
            action: "Play",
            params: ["InstanceID": "0"]
        )

        let snapshot = try #require(mock.lastSnapshot)
        #expect(snapshot.urlString == "http://192.168.1.50:1400/MediaRenderer/AVTransport/Control")
    }
}
