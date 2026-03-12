import Testing
@testable import SonoBarKit

/// Mock HTTP client that captures requests for test assertion.
final class CapturingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
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

/// Builds a minimal valid SOAP response envelope for testing.
func makeEmptyResponse(action: String, service: SonosService) -> Data {
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
