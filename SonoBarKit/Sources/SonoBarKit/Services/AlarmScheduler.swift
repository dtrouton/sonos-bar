// SonoBarKit/Sources/SonoBarKit/Services/AlarmScheduler.swift

import Foundation

/// Manages Sonos alarms via the AlarmClock UPnP service.
public enum AlarmScheduler {

    /// Lists all alarms configured on the Sonos system.
    public static func listAlarms(client: SOAPClient) async throws -> [SonosAlarm] {
        let result = try await client.callAction(
            service: .alarmClock,
            action: "ListAlarms",
            params: [:]
        )
        guard let alarmXML = result["CurrentAlarmList"] else { return [] }
        return try AlarmListParser.parse(alarmXML)
    }

    /// Creates a new alarm.
    public static func createAlarm(client: SOAPClient, alarm: SonosAlarm) async throws {
        _ = try await client.callAction(
            service: .alarmClock,
            action: "CreateAlarm",
            params: alarmParams(alarm)
        )
    }

    /// Updates an existing alarm (must include alarm ID).
    public static func updateAlarm(client: SOAPClient, alarm: SonosAlarm) async throws {
        var params = alarmParams(alarm)
        params.insert(("ID", alarm.id), at: 0)
        _ = try await client.callAction(
            service: .alarmClock,
            action: "UpdateAlarm",
            params: params
        )
    }

    /// Deletes an alarm by ID.
    public static func deleteAlarm(client: SOAPClient, id: String) async throws {
        _ = try await client.callAction(
            service: .alarmClock,
            action: "DestroyAlarm",
            params: [("ID", id)]
        )
    }

    private static func alarmParams(_ alarm: SonosAlarm) -> [(String, String)] {
        [
            ("StartLocalTime", alarm.startLocalTime),
            ("Duration", alarm.duration),
            ("Recurrence", alarm.recurrence),
            ("Enabled", alarm.enabled ? "1" : "0"),
            ("RoomUUID", alarm.roomUUID),
            ("ProgramURI", alarm.programURI),
            ("ProgramMetaData", alarm.programMetaData),
            ("PlayMode", alarm.playMode),
            ("Volume", "\(alarm.volume)"),
            ("IncludeLinkedZones", alarm.includeLinkedZones ? "1" : "0")
        ]
    }
}

// MARK: - AlarmListParser

/// Parses the XML alarm list from ListAlarms response.
enum AlarmListParser {
    static func parse(_ xml: String) throws -> [SonosAlarm] {
        guard let data = xml.data(using: .utf8) else {
            throw SOAPError(code: -1, message: "Failed to encode alarm XML")
        }
        let delegate = AlarmXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? SOAPError(code: -1, message: "Alarm XML parse failed")
        }
        return delegate.alarms
    }
}

private final class AlarmXMLDelegate: NSObject, XMLParserDelegate {
    var alarms: [SonosAlarm] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attr: [String: String] = [:]
    ) {
        guard elementName == "Alarm" else { return }
        let alarm = SonosAlarm(
            id: attr["ID"] ?? "",
            startLocalTime: attr["StartLocalTime"] ?? "",
            recurrence: attr["Recurrence"] ?? "DAILY",
            roomUUID: attr["RoomUUID"] ?? "",
            programURI: attr["ProgramURI"] ?? "",
            programMetaData: attr["ProgramMetaData"] ?? "",
            playMode: attr["PlayMode"] ?? "NORMAL",
            volume: Int(attr["Volume"] ?? "20") ?? 20,
            duration: attr["Duration"] ?? "01:00:00",
            enabled: attr["Enabled"] == "1",
            includeLinkedZones: attr["IncludeLinkedZones"] == "1"
        )
        alarms.append(alarm)
    }
}
