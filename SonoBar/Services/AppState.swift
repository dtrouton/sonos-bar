// SonoBar/Services/AppState.swift
import SwiftUI
import SonoBarKit

/// Per-room playback summary for the Rooms list.
struct RoomSummary: Equatable {
    let transportState: TransportState
    let trackTitle: String?
    let trackArtist: String?
}

@MainActor
@Observable
final class AppState {
    let deviceManager = DeviceManager()
    private let ssdp = SSDPDiscovery()
    private let settings = SettingsStore()
    private var eventListener: UPnPEventListener?
    private var isDiscovering = false

    var playbackState = PlaybackState(transportState: .stopped, volume: 0, isMuted: false)
    var isLoading = true
    private(set) var activeController: PlaybackController?
    /// Playback summary keyed by device UUID, populated for all rooms.
    var roomStates: [String: RoomSummary] = [:]

    func startDiscovery() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        isLoading = true

        // Run SSDP discovery
        let results = await ssdp.scan()
        isLoading = false

        if !results.isEmpty {
            // Fetch zone group topology from the first discovered speaker
            let client = SOAPClient(host: results[0].ip)
            if let response = try? await client.callAction(
                service: .zoneGroupTopology,
                action: "GetZoneGroupState",
                params: [:]
            ), let xml = response["ZoneGroupState"] {
                try? deviceManager.updateFromZoneGroupState(xml)
            }
            // Cache for next launch
            settings.saveSpeakers(deviceManager.devices.map {
                (uuid: $0.uuid, ip: $0.ip, roomName: $0.roomName)
            })
        }

        // Restore active device after topology update
        if let savedUUID = settings.activeDeviceUUID {
            deviceManager.setActiveDevice(uuid: savedUUID)
        }

        updateActiveController()
        await refreshPlayback()
        await refreshAllRooms()
    }

    func refreshPlayback() async {
        guard let controller = activeController else { return }
        let transportState = (try? await controller.getTransportState()) ?? .stopped
        let currentTrack = try? await controller.getPositionInfo()
        let volume = (try? await controller.getVolume()) ?? 0
        let isMuted = (try? await controller.getMute()) ?? false
        playbackState = PlaybackState(
            transportState: transportState,
            volume: volume,
            isMuted: isMuted,
            currentTrack: currentTrack
        )
    }

    func selectRoom(uuid: String) {
        deviceManager.setActiveDevice(uuid: uuid)
        settings.activeDeviceUUID = uuid
        updateActiveController()
        Task { await refreshPlayback() }
    }

    func ungroupDevice(uuid: String) async {
        guard let device = deviceManager.devices.first(where: { $0.uuid == uuid }) else { return }
        let client = SOAPClient(host: device.ip)
        try? await GroupManager.ungroup(client: client)
        await startDiscovery()
    }

    /// Queries each group coordinator in parallel to get playback state for all rooms.
    func refreshAllRooms() async {
        let groups = deviceManager.groups
        // Query each group coordinator concurrently
        await withTaskGroup(of: (String, RoomSummary)?.self) { taskGroup in
            for group in groups {
                guard let coordinatorMember = group.members.first(where: { $0.uuid == group.coordinatorUUID }),
                      !coordinatorMember.ip.isEmpty else { continue }

                let coordinatorIP = coordinatorMember.ip

                taskGroup.addTask { @Sendable in
                    let client = SOAPClient(host: coordinatorIP)
                    let controller = PlaybackController(client: client)
                    let transport = (try? await controller.getTransportState()) ?? .stopped
                    let track = try? await controller.getPositionInfo()
                    let summary = RoomSummary(
                        transportState: transport,
                        trackTitle: track?.title,
                        trackArtist: track?.artist
                    )
                    // Return coordinator UUID as key; we'll map to all members below
                    return (group.coordinatorUUID, summary)
                }
            }

            var coordinatorSummaries: [String: RoomSummary] = [:]
            for await result in taskGroup {
                if let (uuid, summary) = result {
                    coordinatorSummaries[uuid] = summary
                }
            }

            // Map each coordinator's state to all members in that group
            var newStates: [String: RoomSummary] = [:]
            for group in groups {
                if let summary = coordinatorSummaries[group.coordinatorUUID] {
                    for member in group.members {
                        newStates[member.uuid] = summary
                    }
                }
            }
            roomStates = newStates
        }
    }

    private func updateActiveController() {
        guard let device = deviceManager.activeDevice,
              let ip = deviceManager.coordinatorIP(for: device.uuid) else {
            activeController = nil
            return
        }
        activeController = PlaybackController(client: SOAPClient(host: ip))
    }
}
