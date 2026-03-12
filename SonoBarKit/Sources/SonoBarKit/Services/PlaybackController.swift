// PlaybackController.swift
// SonoBarKit
//
// High-level playback control interface wrapping SOAPClient for Sonos speaker commands.

/// Controls playback, volume, and transport on a single Sonos speaker via SOAP.
public final class PlaybackController: Sendable {

    private let client: SOAPClient

    public init(client: SOAPClient) {
        self.client = client
    }

    // MARK: - Transport Controls

    /// Starts or resumes playback.
    public func play() async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "Play",
            params: [("InstanceID", "0"), ("Speed", "1")]
        )
    }

    /// Pauses playback.
    public func pause() async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "Pause",
            params: [("InstanceID", "0")]
        )
    }

    /// Stops playback.
    public func stop() async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "Stop",
            params: [("InstanceID", "0")]
        )
    }

    /// Skips to the next track.
    public func next() async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "Next",
            params: [("InstanceID", "0")]
        )
    }

    /// Skips to the previous track.
    public func previous() async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "Previous",
            params: [("InstanceID", "0")]
        )
    }

    /// Seeks to a specific position in the current track.
    /// - Parameter target: Time position in "H:MM:SS" format.
    public func seek(to target: String) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "Seek",
            params: [("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", target)]
        )
    }

    // MARK: - Transport State

    /// Gets the current transport state.
    public func getTransportState() async throws -> TransportState {
        let result = try await client.callAction(
            service: .avTransport,
            action: "GetTransportInfo",
            params: [("InstanceID", "0")]
        )
        guard let stateString = result["CurrentTransportState"],
              let state = TransportState(rawValue: stateString) else {
            throw SOAPError(code: -1, message: "Unknown transport state")
        }
        return state
    }

    /// Gets the current position/track info.
    public func getPositionInfo() async throws -> TrackInfo? {
        let result = try await client.callAction(
            service: .avTransport,
            action: "GetPositionInfo",
            params: [("InstanceID", "0")]
        )
        return TrackInfo(from: result)
    }

    // MARK: - Volume Controls

    /// Sets the speaker volume (clamped to 0-100).
    public func setVolume(_ level: Int) async throws {
        let clamped = min(100, max(0, level))
        _ = try await client.callAction(
            service: .renderingControl,
            action: "SetVolume",
            params: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(clamped)")]
        )
    }

    /// Gets the current speaker volume.
    public func getVolume() async throws -> Int {
        let result = try await client.callAction(
            service: .renderingControl,
            action: "GetVolume",
            params: [("InstanceID", "0"), ("Channel", "Master")]
        )
        return Int(result["CurrentVolume"] ?? "0") ?? 0
    }

    /// Sets the mute state.
    public func setMute(_ muted: Bool) async throws {
        _ = try await client.callAction(
            service: .renderingControl,
            action: "SetMute",
            params: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredMute", muted ? "1" : "0")]
        )
    }

    /// Gets the current mute state.
    public func getMute() async throws -> Bool {
        let result = try await client.callAction(
            service: .renderingControl,
            action: "GetMute",
            params: [("InstanceID", "0"), ("Channel", "Master")]
        )
        return result["CurrentMute"] == "1"
    }

    // MARK: - Group Volume

    /// Sets the group volume (clamped to 0-100).
    public func setGroupVolume(_ level: Int) async throws {
        let clamped = min(100, max(0, level))
        _ = try await client.callAction(
            service: .groupRenderingControl,
            action: "SetGroupVolume",
            params: [("InstanceID", "0"), ("DesiredVolume", "\(clamped)")]
        )
    }

    /// Gets the current group volume.
    public func getGroupVolume() async throws -> Int {
        let result = try await client.callAction(
            service: .groupRenderingControl,
            action: "GetGroupVolume",
            params: [("InstanceID", "0")]
        )
        return Int(result["CurrentVolume"] ?? "0") ?? 0
    }

    // MARK: - Play URI

    /// Plays a URI with optional metadata.
    public func playURI(_ uri: String, metadata: String) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "SetAVTransportURI",
            params: [("InstanceID", "0"), ("CurrentURI", uri), ("CurrentURIMetaData", metadata)]
        )
        try await play()
    }
}
