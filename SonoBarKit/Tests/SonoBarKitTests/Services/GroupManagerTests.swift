import Testing
@testable import SonoBarKit

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
