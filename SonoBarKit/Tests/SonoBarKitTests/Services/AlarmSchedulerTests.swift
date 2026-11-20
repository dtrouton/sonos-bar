// SonoBarKit/Tests/SonoBarKitTests/Services/AlarmSchedulerTests.swift
import Foundation
import Testing
@testable import SonoBarKit

@Suite("AlarmScheduler Tests")
struct AlarmSchedulerTests {

    private func makeListAlarmsResponse(ids: [Int] = [1], timeAttribute: String = "StartTime") -> Data {
        let alarms = ids.map { id in
            """
            &lt;Alarm ID="\(id)" \(timeAttribute)="07:00:00" Duration="01:00:00" Recurrence="WEEKDAYS" Enabled="1" RoomUUID="RINCON_AAA" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="NORMAL" Volume="20" IncludeLinkedZones="0"/&gt;
            """
        }.joined(separator: "\n")
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:ListAlarmsResponse xmlns:u="urn:schemas-upnp-org:service:AlarmClock:1">
        <CurrentAlarmList>&lt;Alarms&gt;
        \(alarms)
        &lt;/Alarms&gt;</CurrentAlarmList>
        </u:ListAlarmsResponse>
        </s:Body>
        </s:Envelope>
        """
        return Data(xml.utf8)
    }

    @Test(arguments: ["StartTime", "StartLocalTime"])
    func testListAlarmsParsesResponse(timeAttribute: String) async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeListAlarmsResponse(timeAttribute: timeAttribute)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let alarms = try await AlarmScheduler.listAlarms(client: client)

        #expect(alarms.count == 1)
        let alarm = alarms[0]
        #expect(alarm.id == "1")
        #expect(alarm.startLocalTime == "07:00:00")
        #expect(alarm.displayTime == "7:00 AM")
        #expect(alarm.startTimeComponents == DateComponents(hour: 7, minute: 0, second: 0))
        #expect(alarm.recurrence == "WEEKDAYS")
        #expect(alarm.repeatingDays == [1, 2, 3, 4, 5])
        #expect(alarm.enabled == true)
        #expect(alarm.volume == 20)
        #expect(alarm.roomUUID == "RINCON_AAA")
    }

    @Test func testCreateAlarmSendsCorrectParams() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "CreateAlarm", service: .alarmClock)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let alarm = SonosAlarm(
            id: "",
            startLocalTime: "07:00:00",
            recurrence: "WEEKDAYS",
            roomUUID: "RINCON_AAA",
            programURI: "x-rincon-buzzer:0",
            volume: 20
        )

        try await AlarmScheduler.createAlarm(client: client, alarm: alarm)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:CreateAlarm"))
        #expect(body.contains("<StartLocalTime>07:00:00</StartLocalTime>"))
        #expect(body.contains("<Recurrence>WEEKDAYS</Recurrence>"))
        #expect(body.contains("<RoomUUID>RINCON_AAA</RoomUUID>"))
        #expect(body.contains("<PlayMode>NORMAL</PlayMode>"))
        #expect(body.contains("<Volume>20</Volume>"))
        #expect(body.contains("<Enabled>1</Enabled>"))
    }

    @Test func testDeleteAlarmSendsCorrectID() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "DestroyAlarm", service: .alarmClock)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await AlarmScheduler.deleteAlarm(client: client, id: "42")

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:DestroyAlarm"))
        #expect(body.contains("<ID>42</ID>"))
    }

    @Test func testEditingAnAlarmPreservesItsSonosSettings() async throws {
        let original = SonosAlarm(
            id: "42", startLocalTime: "07:00:30", recurrence: "ONCE", roomUUID: "RINCON_AAA",
            programURI: "x-sonosapi-stream:station", programMetaData: "<DIDL/>",
            playMode: "SHUFFLE", volume: 17, duration: "00:45:00", enabled: false, includeLinkedZones: true
        )
        let edited = original.updating(startLocalTime: "17:45:00", volume: 30)
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "UpdateAlarm", service: .alarmClock)
        let client = SOAPClient(host: "sonos", httpClient: mock)

        try await AlarmScheduler.updateAlarm(client: client, alarm: edited)

        let body = try #require(mock.lastBodyString)
        #expect(edited.displayTime == "5:45 PM")
        #expect(edited.repeatingDays == nil)
        #expect(body.contains("<ID>42</ID>"))
        #expect(body.contains("<StartLocalTime>17:45:00</StartLocalTime>"))
        #expect(body.contains("<Recurrence>ONCE</Recurrence>"))
        #expect(body.contains("<Volume>30</Volume>"))
        #expect(body.contains("<Duration>00:45:00</Duration>"))
        #expect(body.contains("<Enabled>0</Enabled>"))
        #expect(body.contains("<PlayMode>SHUFFLE</PlayMode>"))
        #expect(body.contains("<IncludeLinkedZones>1</IncludeLinkedZones>"))
        #expect(body.contains("<ProgramURI>x-sonosapi-stream:station</ProgramURI>"))
        #expect(body.contains("<ProgramMetaData>&lt;DIDL/&gt;</ProgramMetaData>"))
    }

    @Test(arguments: [URLError.Code.cannotConnectToHost, .timedOut])
    func testRetryAlarmSaveUsesSameDraftWithoutCreatingADuplicate(failure: URLError.Code) async throws {
        let mock = AlarmRetryHTTPClient(
            failure: failure,
            existing: makeListAlarmsResponse(),
            afterCreate: makeListAlarmsResponse(ids: [1, 2])
        )
        let client = SOAPClient(host: "sonos", httpClient: mock)
        let alarm = SonosAlarm(
            id: "", startLocalTime: "07:00:00", recurrence: "WEEKDAYS", roomUUID: "RINCON_AAA",
            programURI: "x-rincon-buzzer:0", volume: 20
        )
        var attempt = AlarmScheduler.CreationAttempt(alarm: alarm)
        do {
            try await attempt.save(client: client)
            Issue.record("The first alarm save should surface the connection error.")
        } catch let error as URLError {
            #expect(error.code == failure)
        }

        #expect(attempt.alarm == alarm)
        try await attempt.save(client: client)
        #expect(await mock.createRequests == 1)
    }
}

private actor AlarmRetryHTTPClient: HTTPClientProtocol {
    let failure: URLError.Code
    let existing: Data
    let afterCreate: Data
    private var listRequests = 0
    private(set) var createRequests = 0

    init(failure: URLError.Code, existing: Data, afterCreate: Data) {
        self.failure = failure
        self.existing = existing
        self.afterCreate = afterCreate
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body: Data
        if request.value(forHTTPHeaderField: "SOAPACTION")?.contains("#ListAlarms") == true {
            listRequests += 1
            if listRequests == 1 && failure == .cannotConnectToHost { throw URLError(failure) }
            body = createRequests == 0 ? existing : afterCreate
        } else {
            createRequests += 1
            if failure == .timedOut && createRequests == 1 { throw URLError(failure) }
            body = makeEmptyResponse(action: "CreateAlarm", service: .alarmClock)
        }
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (body, response)
    }
}
