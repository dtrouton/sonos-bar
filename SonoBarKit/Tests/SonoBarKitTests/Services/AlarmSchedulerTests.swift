// SonoBarKit/Tests/SonoBarKitTests/Services/AlarmSchedulerTests.swift
import Testing
@testable import SonoBarKit

@Suite("AlarmScheduler Tests")
struct AlarmSchedulerTests {

    private func makeListAlarmsResponse() -> Data {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:ListAlarmsResponse xmlns:u="urn:schemas-upnp-org:service:AlarmClock:1">
        <CurrentAlarmList>&lt;Alarms&gt;&lt;Alarm ID="1" StartLocalTime="07:00:00" Duration="01:00:00" Recurrence="WEEKDAYS" Enabled="1" RoomUUID="RINCON_AAA" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="NORMAL" Volume="20" IncludeLinkedZones="0"/&gt;&lt;/Alarms&gt;</CurrentAlarmList>
        </u:ListAlarmsResponse>
        </s:Body>
        </s:Envelope>
        """
        return Data(xml.utf8)
    }

    @Test func testListAlarmsParsesResponse() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeListAlarmsResponse()
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let alarms = try await AlarmScheduler.listAlarms(client: client)

        #expect(alarms.count == 1)
        let alarm = alarms[0]
        #expect(alarm.id == "1")
        #expect(alarm.startLocalTime == "07:00:00")
        #expect(alarm.recurrence == "WEEKDAYS")
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
}
