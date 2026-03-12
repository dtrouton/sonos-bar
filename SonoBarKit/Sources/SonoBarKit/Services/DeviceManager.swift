// DeviceManager.swift
// SonoBarKit
//
// Manages discovered Sonos devices and their zone group topology.
// Observable for SwiftUI integration.

import Observation

/// Manages discovered Sonos devices and their group topology.
/// Tracks the active (selected) device and provides coordinator lookups.
@MainActor
@Observable
public final class DeviceManager {

    /// All discovered Sonos devices, derived from zone group topology.
    public private(set) var devices: [SonosDevice] = []

    /// Current zone group topology.
    public private(set) var groups: [ZoneGroup] = []

    /// The currently selected device for playback control.
    public private(set) var activeDevice: SonosDevice?

    public init() {}

    // MARK: - Public API

    /// Updates devices and groups from a ZoneGroupState XML string.
    /// Preserves the active device selection if the device is still present.
    public func updateFromZoneGroupState(_ xml: String) throws {
        let parsedGroups = try ZoneGroupParser.parse(xml)

        // Build device list from all group members, preserving existing state
        var newDevices: [SonosDevice] = []
        for group in parsedGroups {
            for member in group.members {
                let existing = devices.first { $0.uuid == member.uuid }
                let device = SonosDevice(
                    uuid: member.uuid,
                    ip: member.ip,
                    roomName: member.zoneName,
                    modelName: existing?.modelName ?? "",
                    isReachable: existing?.isReachable ?? true
                )
                newDevices.append(device)
            }
        }

        self.groups = parsedGroups
        self.devices = newDevices

        // Preserve active device if still present
        if let activeUUID = activeDevice?.uuid {
            self.activeDevice = newDevices.first { $0.uuid == activeUUID }
        }
    }

    /// Sets the active device by UUID.
    public func setActiveDevice(uuid: String) {
        self.activeDevice = devices.first { $0.uuid == uuid }
    }

    /// Returns the coordinator's IP address for a given device UUID.
    /// Finds which group the device belongs to, then returns the coordinator's IP.
    public func coordinatorIP(for uuid: String) -> String? {
        guard let group = group(for: uuid) else { return nil }
        return group.members.first { $0.uuid == group.coordinatorUUID }?.ip
    }

    /// Returns the ZoneGroup that contains the given device UUID.
    public func group(for uuid: String) -> ZoneGroup? {
        return groups.first { group in
            group.members.contains { $0.uuid == uuid }
        }
    }

    /// Returns whether the given UUID is a group coordinator.
    public func isCoordinator(_ uuid: String) -> Bool {
        return groups.contains { $0.coordinatorUUID == uuid }
    }
}
