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

    @Test func testClearQueueSendsRemoveAllTracks() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "RemoveAllTracksFromQueue", service: .avTransport)
        let controller = PlaybackController(client: SOAPClient(host: "192.168.1.10", httpClient: mock))
        try await controller.clearQueue()
        #expect(mock.lastBodyString?.contains("RemoveAllTracksFromQueue") == true)
    }

    @Test func testAddToQueueSendsCorrectParams() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "AddURIToQueue", service: .avTransport)
        let controller = PlaybackController(client: SOAPClient(host: "192.168.1.10", httpClient: mock))
        try await controller.addToQueue(uri: "http://plex/file.mp3", metadata: "<DIDL/>")
        let body = mock.lastBodyString ?? ""
        #expect(body.contains("AddURIToQueue"))
        #expect(body.contains("http://plex/file.mp3"))
        #expect(body.contains("<DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued>"))
        #expect(body.contains("<EnqueueAsNext>0</EnqueueAsNext>"))
    }

    @Test func testPlayNextInsertsAtRequestedPosition() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "AddURIToQueue", service: .avTransport)
        let controller = PlaybackController(client: SOAPClient(host: "192.168.1.10", httpClient: mock))

        try await controller.addToQueue(uri: "http://plex/file.mp3", metadata: "", position: 4, enqueueAsNext: true)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<DesiredFirstTrackNumberEnqueued>4</DesiredFirstTrackNumberEnqueued>"))
        #expect(body.contains("<EnqueueAsNext>1</EnqueueAsNext>"))
    }

    @Test(arguments: [true, false])
    func testPlayQueuedTrackSeeksBeforePlaying(queueAlreadySelected: Bool) async throws {
        let queueURI = "x-rincon-queue:RINCON_TEST#0"
        let currentURI = queueAlreadySelected ? queueURI : "x-sonos-htastream:RINCON_TEST:spdif"
        let mock = CapturingHTTPClient()
        mock.responseData = Data("""
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetMediaInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <CurrentURI>\(currentURI)</CurrentURI>
            </u:GetMediaInfoResponse>
          </s:Body>
        </s:Envelope>
        """.utf8)
        let controller = PlaybackController(client: SOAPClient(host: "192.168.1.10", httpClient: mock))

        try await controller.playQueuedTrack(7, queueURI: queueURI)

        let actions = mock.requests.compactMap { $0.value(forHTTPHeaderField: "SOAPACTION") }
        let expected = queueAlreadySelected
            ? ["GetMediaInfo", "Seek", "Play"]
            : ["GetMediaInfo", "SetAVTransportURI", "Seek", "Play"]
        #expect(actions == expected.map { "\"urn:schemas-upnp-org:service:AVTransport:1#\($0)\"" })
        let seekRequest = try #require(mock.requests.dropLast().last)
        let seekBody = String(decoding: try #require(seekRequest.httpBody), as: UTF8.self)
        #expect(seekBody.contains("<Unit>TRACK_NR</Unit>"))
        #expect(seekBody.contains("<Target>7</Target>"))
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
