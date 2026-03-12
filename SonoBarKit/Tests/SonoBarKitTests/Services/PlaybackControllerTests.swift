import Testing
@testable import SonoBarKit

@Suite("PlaybackController Tests")
struct PlaybackControllerTests {

    @Test func testPlaySendsCorrectAction() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "Play", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)
        let controller = PlaybackController(client: client)

        try await controller.play()

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:Play"))
        #expect(body.contains("<InstanceID>0</InstanceID>"))
        #expect(body.contains("<Speed>1</Speed>"))
    }

    @Test func testPauseSendsCorrectAction() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "Pause", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)
        let controller = PlaybackController(client: client)

        try await controller.pause()

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:Pause"))
        #expect(body.contains("<InstanceID>0</InstanceID>"))
    }

    @Test func testSetVolumeSendsCorrectValue() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "SetVolume", service: .renderingControl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)
        let controller = PlaybackController(client: client)

        try await controller.setVolume(42)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:SetVolume"))
        #expect(body.contains("<DesiredVolume>42</DesiredVolume>"))
        #expect(body.contains("<InstanceID>0</InstanceID>"))
        #expect(body.contains("<Channel>Master</Channel>"))
    }

    @Test func testSetVolumeClamps() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "SetVolume", service: .renderingControl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)
        let controller = PlaybackController(client: client)

        // Test clamping above 100
        try await controller.setVolume(150)
        var body = try #require(mock.lastBodyString)
        #expect(body.contains("<DesiredVolume>100</DesiredVolume>"))

        // Test clamping below 0
        try await controller.setVolume(-10)
        body = try #require(mock.lastBodyString)
        #expect(body.contains("<DesiredVolume>0</DesiredVolume>"))
    }

    @Test func testGetTransportStateParsesResponse() async throws {
        let mock = CapturingHTTPClient()
        let responseXML = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <CurrentTransportState>PLAYING</CurrentTransportState>
          <CurrentTransportStatus>OK</CurrentTransportStatus>
          <CurrentSpeed>1</CurrentSpeed>
        </u:GetTransportInfoResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(responseXML.utf8)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)
        let controller = PlaybackController(client: client)

        let state = try await controller.getTransportState()
        #expect(state == .playing)
    }
}
