// SonoBarKit/Sources/SonoBarKit/Models/SonosAlarm.swift

import Foundation

/// A Sonos alarm definition.
public struct SonosAlarm: Identifiable, Sendable, Equatable {
    public let id: String
    public let startLocalTime: String
    public let recurrence: String
    public let roomUUID: String
    public let programURI: String
    public let programMetaData: String
    public let playMode: String
    public let volume: Int
    public let duration: String
    public let enabled: Bool
    public let includeLinkedZones: Bool

    public init(
        id: String,
        startLocalTime: String,
        recurrence: String,
        roomUUID: String,
        programURI: String,
        programMetaData: String = "",
        playMode: String = "NORMAL",
        volume: Int,
        duration: String = "01:00:00",
        enabled: Bool = true,
        includeLinkedZones: Bool = false
    ) {
        self.id = id
        self.startLocalTime = startLocalTime
        self.recurrence = recurrence
        self.roomUUID = roomUUID
        self.programURI = programURI
        self.programMetaData = programMetaData
        self.playMode = playMode
        self.volume = volume
        self.duration = duration
        self.enabled = enabled
        self.includeLinkedZones = includeLinkedZones
    }

    /// Human-readable recurrence text.
    public var recurrenceText: String {
        switch recurrence {
        case "DAILY": return "Daily"
        case "WEEKDAYS": return "Weekdays"
        case "WEEKENDS": return "Weekends"
        case "ONCE": return "Once"
        default:
            // ON_0123456 format: 0=Sun, 1=Mon, ..., 6=Sat
            if recurrence.hasPrefix("ON_") {
                let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let digits = recurrence.dropFirst(3)
                let names = digits.compactMap { c -> String? in
                    guard let idx = Int(String(c)), idx >= 0, idx <= 6 else { return nil }
                    return dayNames[idx]
                }
                return names.joined(separator: ", ")
            }
            return recurrence
        }
    }

    /// The start time formatted for display (e.g., "7:00 AM").
    public var displayTime: String {
        guard let time = startTimeComponents, let hour = time.hour, let minute = time.minute else {
            return "Time unavailable"
        }
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h12, minute, ampm)
    }

    public var startTimeComponents: DateComponents? {
        let parts = startLocalTime.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let hour = Int(parts[0]), (0..<24).contains(hour),
              let minute = Int(parts[1]), (0..<60).contains(minute) else { return nil }
        let second = parts.count == 3 ? Int(parts[2]) : 0
        guard let second, (0..<60).contains(second) else { return nil }
        return DateComponents(hour: hour, minute: minute, second: second)
    }

    /// Sunday is day 0. A one-time or unrecognized schedule has no set of repeating days.
    public var repeatingDays: Set<Int>? {
        switch recurrence {
        case "DAILY": return Set(0...6)
        case "WEEKDAYS": return Set(1...5)
        case "WEEKENDS": return [0, 6]
        default:
            guard recurrence.hasPrefix("ON_") else { return nil }
            let digits = recurrence.dropFirst(3)
            let days = digits.compactMap { Int(String($0)) }.filter { (0...6).contains($0) }
            guard !days.isEmpty, days.count == digits.count else { return nil }
            return Set(days)
        }
    }

    /// Copies the alarm with new schedule fields and preserves its Sonos playback settings.
    public func updating(
        startLocalTime: String? = nil, recurrence: String? = nil, roomUUID: String? = nil,
        volume: Int? = nil, enabled: Bool? = nil
    ) -> SonosAlarm {
        SonosAlarm(
            id: id, startLocalTime: startLocalTime ?? self.startLocalTime,
            recurrence: recurrence ?? self.recurrence, roomUUID: roomUUID ?? self.roomUUID,
            programURI: programURI, programMetaData: programMetaData, playMode: playMode,
            volume: volume ?? self.volume, duration: duration, enabled: enabled ?? self.enabled,
            includeLinkedZones: includeLinkedZones
        )
    }
}
