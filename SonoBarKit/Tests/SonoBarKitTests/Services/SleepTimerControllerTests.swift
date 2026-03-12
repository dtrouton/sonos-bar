// SonoBarKit/Tests/SonoBarKitTests/Services/SleepTimerControllerTests.swift
import Testing
@testable import SonoBarKit

@Suite("SleepTimerController Tests")
struct SleepTimerControllerTests {

    @Test func testSetSleepTimerConvertsMinutesToHMS() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "ConfigureSleepTimer", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await SleepTimerController.setSleepTimer(client: client, minutes: 45)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:ConfigureSleepTimer"))
        #expect(body.contains("<NewSleepTimerDuration>00:45:00</NewSleepTimerDuration>"))
    }

    @Test func testSetSleepTimerHandlesHours() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "ConfigureSleepTimer", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await SleepTimerController.setSleepTimer(client: client, minutes: 90)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<NewSleepTimerDuration>01:30:00</NewSleepTimerDuration>"))
    }

    @Test func testGetRemainingTimeReturnsString() async throws {
        let mock = CapturingHTTPClient()
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetRemainingSleepTimerDurationResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        <RemainSleepTimerDuration>00:23:45</RemainSleepTimerDuration>
        </u:GetRemainingSleepTimerDurationResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(xml.utf8)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let remaining = try await SleepTimerController.getRemainingTime(client: client)
        #expect(remaining == "00:23:45")
    }

    @Test func testGetRemainingTimeReturnsNilWhenEmpty() async throws {
        let mock = CapturingHTTPClient()
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetRemainingSleepTimerDurationResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        <RemainSleepTimerDuration></RemainSleepTimerDuration>
        </u:GetRemainingSleepTimerDurationResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(xml.utf8)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let remaining = try await SleepTimerController.getRemainingTime(client: client)
        #expect(remaining == nil)
    }

    @Test func testCancelSleepTimerSendsEmptyDuration() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "ConfigureSleepTimer", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await SleepTimerController.cancelSleepTimer(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<NewSleepTimerDuration></NewSleepTimerDuration>"))
    }
}
