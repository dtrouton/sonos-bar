// SonosDevice.swift
// SonoBarKit
//
// Represents a Sonos speaker discovered on the local network.

/// A Sonos speaker on the local network.
public struct SonosDevice: Identifiable, Sendable, Equatable {
    public let uuid: String
    public let ip: String
    public let roomName: String
    public let modelName: String
    public var isReachable: Bool

    public var id: String { uuid }

    public init(
        uuid: String,
        ip: String,
        roomName: String,
        modelName: String,
        isReachable: Bool = true
    ) {
        self.uuid = uuid
        self.ip = ip
        self.roomName = roomName
        self.modelName = modelName
        self.isReachable = isReachable
    }

    /// Returns a copy with the given reachability flag.
    public func with(isReachable: Bool) -> SonosDevice {
        var copy = self
        copy.isReachable = isReachable
        return copy
    }
}
