// SonoBarKit/Sources/SonoBarKit/Services/SleepTimerController.swift

/// Controls the Sonos sleep timer via AVTransport.
public enum SleepTimerController {

    /// Sets a sleep timer for the given number of minutes.
    public static func setSleepTimer(client: SOAPClient, minutes: Int) async throws {
        let hours = minutes / 60
        let mins = minutes % 60
        let duration = String(format: "%02d:%02d:00", hours, mins)
        _ = try await client.callAction(
            service: .avTransport,
            action: "ConfigureSleepTimer",
            params: [("InstanceID", "0"), ("NewSleepTimerDuration", duration)]
        )
    }

    /// Gets the remaining sleep timer duration as "HH:MM:SS", or nil if no timer active.
    public static func getRemainingTime(client: SOAPClient) async throws -> String? {
        let result = try await client.callAction(
            service: .avTransport,
            action: "GetRemainingSleepTimerDuration",
            params: [("InstanceID", "0")]
        )
        #if DEBUG
        print("[SleepTimer] Raw response keys: \(Array(result.keys))")
        print("[SleepTimer] Raw response: \(result)")
        #endif
        // Try both known key variants
        let remaining = result["RemainingSleepTimerDuration"] ?? result["RemainSleepTimerDuration"]
        guard let remaining, !remaining.isEmpty else { return nil }
        return remaining
    }

    /// Cancels the active sleep timer.
    public static func cancelSleepTimer(client: SOAPClient) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "ConfigureSleepTimer",
            params: [("InstanceID", "0"), ("NewSleepTimerDuration", "")]
        )
    }
}
