import Testing
@testable import SonoBarKit

// MARK: - Test Mock

/// Mock HTTP client that captures the request body for assertion.
private final class CapturingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    var lastRequest: URLRequest?
    var responseData: Data = Data()
    var responseStatusCode: Int = 200

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let url = request.url ?? URL(string: "http://localhost")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (responseData, response)
    }

    var lastBodyString: String? {
        lastRequest?.httpBody.flatMap { String(data: $0, encoding: .utf8) }
    }
}

// MARK: - Helper

private func makeEmptyResponse(action: String, service: SonosService) -> Data {
    let xml = """
    <?xml version="1.0"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
    <s:Body>
    <u:\(action)Response xmlns:u="\(service.serviceType)">
    </u:\(action)Response>
    </s:Body>
    </s:Envelope>
    """
    return Data(xml.utf8)
}

@Suite("GroupManager Tests")
struct GroupManagerTests {

    @Test func testGroupSendsCorrectURI() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "SetAVTransportURI", service: .avTransport)
        let memberClient = SOAPClient(host: "192.168.1.11", httpClient: mock)

        try await GroupManager.joinToCoordinator(
            memberClient: memberClient,
            coordinatorUUID: "RINCON_AAA"
        )

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:SetAVTransportURI"))
        #expect(body.contains("<CurrentURI>x-rincon:RINCON_AAA</CurrentURI>"))
        #expect(body.contains("<InstanceID>0</InstanceID>"))
    }

    @Test func testUngroupSendsCorrectAction() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(
            action: "BecomeCoordinatorOfStandaloneGroup",
            service: .avTransport
        )
        let client = SOAPClient(host: "192.168.1.11", httpClient: mock)

        try await GroupManager.ungroup(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:BecomeCoordinatorOfStandaloneGroup"))
        #expect(body.contains("<InstanceID>0</InstanceID>"))
    }
}
