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

    private var activeClient: SOAPClient? {
        guard let device = deviceManager.activeDevice,
              let ip = deviceManager.coordinatorIP(for: device.uuid) else { return nil }
        return SOAPClient(host: ip)
    }

    // MARK: - Browse

    var contentItems: [ContentItem] = []
    var contentError: String? = nil

    func browseFavorites() async {
        contentError = nil
        guard let client = activeClient else { return }
        do {
            contentItems = try await ContentBrowser.browseFavorites(client: client)
        } catch {
            contentError = "Failed to load favorites"
        }
    }

    func browsePlaylists() async {
        contentError = nil
        guard let client = activeClient else { return }
        do {
            contentItems = try await ContentBrowser.browsePlaylists(client: client)
        } catch {
            contentError = "Failed to load playlists"
        }
    }

    func browseQueue() async {
        contentError = nil
        guard let client = activeClient else { return }
        do {
            contentItems = try await ContentBrowser.browseQueue(client: client)
        } catch {
            contentError = "Failed to load queue"
        }
    }

    func playItem(_ item: ContentItem) async {
        guard let client = activeClient else { return }
        do {
            try await ContentBrowser.playItem(client: client, item: item)
            await refreshPlayback()
        } catch {
            contentError = "Failed to play \(item.title)"
        }
    }

    // MARK: - Alarms & Sleep Timer

    var alarms: [SonosAlarm] = []
    var sleepTimerRemaining: String? = nil

    func fetchAlarms() async {
        guard let client = activeClient else { return }
        alarms = (try? await AlarmScheduler.listAlarms(client: client)) ?? []
    }

    func createAlarm(_ alarm: SonosAlarm) async {
        guard let client = activeClient else { return }
        try? await AlarmScheduler.createAlarm(client: client, alarm: alarm)
        await fetchAlarms()
    }

    func toggleAlarm(_ alarm: SonosAlarm) async {
        guard let client = activeClient else { return }
        let toggled = SonosAlarm(
            id: alarm.id,
            startLocalTime: alarm.startLocalTime,
            recurrence: alarm.recurrence,
            roomUUID: alarm.roomUUID,
            programURI: alarm.programURI,
            programMetaData: alarm.programMetaData,
            playMode: alarm.playMode,
            volume: alarm.volume,
            duration: alarm.duration,
            enabled: !alarm.enabled,
            includeLinkedZones: alarm.includeLinkedZones
        )
        try? await AlarmScheduler.updateAlarm(client: client, alarm: toggled)
        await fetchAlarms()
    }

    func deleteAlarm(_ alarm: SonosAlarm) async {
        guard let client = activeClient else { return }
        try? await AlarmScheduler.deleteAlarm(client: client, id: alarm.id)
        await fetchAlarms()
    }

    func setSleepTimer(minutes: Int) async {
        guard let client = activeClient else { return }
        try? await SleepTimerController.setSleepTimer(client: client, minutes: minutes)
        await refreshSleepTimer()
    }

    func cancelSleepTimer() async {
        guard let client = activeClient else { return }
        try? await SleepTimerController.cancelSleepTimer(client: client)
        sleepTimerRemaining = nil
    }

    func refreshSleepTimer() async {
        guard let client = activeClient else { return }
        sleepTimerRemaining = try? await SleepTimerController.getRemainingTime(client: client)
    }
}
