// SonoBarKit/Sources/SonoBarKit/Models/SonosAlarm.swift

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
        let parts = startLocalTime.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return startLocalTime
        }
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h12, minute, ampm)
    }
}
