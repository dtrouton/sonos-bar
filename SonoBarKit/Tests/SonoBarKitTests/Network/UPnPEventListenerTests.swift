import Testing
@testable import SonoBarKit

@Suite("UPnPEventListener Tests")
struct UPnPEventListenerTests {

    @Test func testBuildSubscribeRequest() throws {
        let request = UPnPSubscription.buildSubscribeRequest(
            speakerHost: "192.168.1.42",
            service: .avTransport,
            callbackURL: "http://192.168.1.10:8400/event/avTransport",
            timeout: 3600
        )

        #expect(request.url?.absoluteString == "http://192.168.1.42:1400/MediaRenderer/AVTransport/Event")
        #expect(request.httpMethod == "SUBSCRIBE")
        #expect(request.value(forHTTPHeaderField: "CALLBACK") == "<http://192.168.1.10:8400/event/avTransport>")
        #expect(request.value(forHTTPHeaderField: "NT") == "upnp:event")
        #expect(request.value(forHTTPHeaderField: "TIMEOUT") == "Second-3600")
        // SUBSCRIBE requests should NOT have a SID header
        #expect(request.value(forHTTPHeaderField: "SID") == nil)
    }

    @Test func testBuildSubscribeRequestDefaultTimeout() throws {
        let request = UPnPSubscription.buildSubscribeRequest(
            speakerHost: "192.168.1.42",
            service: .renderingControl,
            callbackURL: "http://192.168.1.10:8400/event/renderingControl"
        )

        #expect(request.url?.absoluteString == "http://192.168.1.42:1400/MediaRenderer/RenderingControl/Event")
        #expect(request.httpMethod == "SUBSCRIBE")
        #expect(request.value(forHTTPHeaderField: "TIMEOUT") == "Second-3600")
    }

    @Test func testBuildRenewRequest() throws {
        let request = UPnPSubscription.buildRenewRequest(
            speakerHost: "192.168.1.42",
            service: .avTransport,
            sid: "uuid:sub-12345",
            timeout: 1800
        )

        #expect(request.url?.absoluteString == "http://192.168.1.42:1400/MediaRenderer/AVTransport/Event")
        #expect(request.httpMethod == "SUBSCRIBE")
        #expect(request.value(forHTTPHeaderField: "SID") == "uuid:sub-12345")
        #expect(request.value(forHTTPHeaderField: "TIMEOUT") == "Second-1800")
        // Renew requests should NOT have CALLBACK or NT headers
        #expect(request.value(forHTTPHeaderField: "CALLBACK") == nil)
        #expect(request.value(forHTTPHeaderField: "NT") == nil)
    }

    @Test func testBuildRenewRequestDefaultTimeout() throws {
        let request = UPnPSubscription.buildRenewRequest(
            speakerHost: "192.168.1.42",
            service: .zoneGroupTopology,
            sid: "uuid:sub-67890"
        )

        #expect(request.url?.absoluteString == "http://192.168.1.42:1400/ZoneGroupTopology/Event")
        #expect(request.value(forHTTPHeaderField: "TIMEOUT") == "Second-3600")
    }

    @Test func testBuildUnsubscribeRequest() throws {
        let request = UPnPSubscription.buildUnsubscribeRequest(
            speakerHost: "192.168.1.42",
            service: .avTransport,
            sid: "uuid:sub-12345"
        )

        #expect(request.url?.absoluteString == "http://192.168.1.42:1400/MediaRenderer/AVTransport/Event")
        #expect(request.httpMethod == "UNSUBSCRIBE")
        #expect(request.value(forHTTPHeaderField: "SID") == "uuid:sub-12345")
        // UNSUBSCRIBE should NOT have CALLBACK, NT, or TIMEOUT headers
        #expect(request.value(forHTTPHeaderField: "CALLBACK") == nil)
        #expect(request.value(forHTTPHeaderField: "NT") == nil)
        #expect(request.value(forHTTPHeaderField: "TIMEOUT") == nil)
    }

    @Test func testCallbackPath() {
        #expect(UPnPEventListener.callbackPath(for: .avTransport) == "/event/avTransport")
        #expect(UPnPEventListener.callbackPath(for: .renderingControl) == "/event/renderingControl")
        #expect(UPnPEventListener.callbackPath(for: .groupRenderingControl) == "/event/groupRenderingControl")
        #expect(UPnPEventListener.callbackPath(for: .zoneGroupTopology) == "/event/zoneGroupTopology")
        #expect(UPnPEventListener.callbackPath(for: .contentDirectory) == "/event/contentDirectory")
        #expect(UPnPEventListener.callbackPath(for: .alarmClock) == "/event/alarmClock")
        #expect(UPnPEventListener.callbackPath(for: .deviceProperties) == "/event/deviceProperties")
    }
}
