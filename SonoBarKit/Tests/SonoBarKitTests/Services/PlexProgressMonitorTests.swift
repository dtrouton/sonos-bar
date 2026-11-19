import Foundation
import Testing
@testable import SonoBarKit

@Suite("Plex progress monitoring")
struct PlexProgressMonitorTests {
    @Test func reportsChapterTransitionsAndPausesWithoutWaitingForHeartbeat() async throws {
        let firstURI = "http://plex/library/parts/1/file.mp3"
        let secondURI = "http://plex/library/parts/2/file.mp3"
        let sonos = SonosProgressResponse()
        let plex = CapturingHTTPClient()
        let controller = PlaybackController(client: SOAPClient(host: "sonos", httpClient: sonos))
        let monitor = PlexProgressMonitor(
            controller: controller,
            client: PlexClient(host: "plex", token: "test-token", httpClient: plex),
            coordinatorUUID: "RINCON_TEST"
        )
        await monitor.recordQueuedTrack(id: "101", uri: firstURI)
        await monitor.recordQueuedTrack(id: "102", uri: secondURI)

        await sonos.setPosition(uri: firstURI, state: .playing, elapsed: "00:04:50")
        #expect(try await controller.getTransportState() == .playing)
        #expect(try await controller.getPositionInfo()?.uri == firstURI)
        await monitor.sample()
        await monitor.sample()
        #expect(plex.requests.count == 1)

        await sonos.setPosition(uri: secondURI, state: .playing, elapsed: "00:00:02")
        await monitor.sample()
        await sonos.setPosition(uri: secondURI, state: .pausedPlayback, elapsed: "00:00:07")
        await monitor.sample()
        await monitor.sample()

        let reports = plex.requests.compactMap { request in
            request.url?.query()
        }
        #expect(reports.count == 3)
        let paused = try #require(reports.last)
        #expect(paused.contains("ratingKey=102"))
        #expect(paused.contains("state=paused"))
        #expect(paused.contains("time=7000"))
        #expect(paused.contains("X-Plex-Client-Identifier=com.sonobar.plex.RINCON_TEST"))
    }

    @Test func ignoresOtherSourcesAndDefersSamplingDuringQueueChanges() async {
        let plexURI = "http://plex/library/parts/1/file.mp3"
        let sonos = SonosProgressResponse()
        let plex = CapturingHTTPClient()
        let monitor = PlexProgressMonitor(
            controller: PlaybackController(client: SOAPClient(host: "sonos", httpClient: sonos)),
            client: PlexClient(host: "plex", token: "test-token", httpClient: plex),
            coordinatorUUID: "RINCON_TEST"
        )
        await monitor.recordQueuedTrack(id: "101", uri: plexURI)
        await sonos.setPosition(uri: "x-sonosapi-stream:radio", state: .playing, elapsed: "00:00:03")
        await monitor.sample()

        await monitor.beginQueueUpdate()
        await sonos.setPosition(uri: plexURI, state: .playing, elapsed: "00:00:00")
        await monitor.sample()
        #expect(plex.requests.isEmpty)

        await monitor.finishQueueUpdate()
        await sonos.setPosition(uri: plexURI, state: .playing, elapsed: "00:01:25")
        await monitor.sample()
        #expect(plex.requests.first?.url?.query()?.contains("time=85000") == true)
    }
}

private actor SonosProgressResponse: HTTPClientProtocol {
    private var uri = ""
    private var state = TransportState.stopped
    private var elapsed = "00:00:00"

    func setPosition(uri: String, state: TransportState, elapsed: String) {
        self.uri = uri
        self.state = state
        self.elapsed = elapsed
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let action: String
        let payload: String
        if request.value(forHTTPHeaderField: "SOAPACTION")?.contains("GetTransportInfo") == true {
            action = "GetTransportInfo"
            payload = "<CurrentTransportState>\(state.rawValue)</CurrentTransportState>"
        } else {
            action = "GetPositionInfo"
            payload = """
            <Track>1</Track>
            <TrackDuration>00:05:00</TrackDuration>
            <RelTime>\(elapsed)</RelTime>
            <TrackURI>\(uri)</TrackURI>
            """
        }
        let data = Data("""
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:\(action)Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              \(payload)
            </u:\(action)Response>
          </s:Body>
        </s:Envelope>
        """.utf8)
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (data, response)
    }
}
