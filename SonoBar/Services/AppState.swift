// SonoBar/Services/AppState.swift
import SwiftUI
import SonoBarKit

@MainActor
@Observable
final class AppState {
    let deviceManager = DeviceManager()
    private let ssdp = SSDPDiscovery()
    private let settings = SettingsStore()
    private var eventListener: UPnPEventListener?

    var playbackState = PlaybackState(transportState: .stopped, volume: 0, isMuted: false)
    var isLoading = true

    /// The SOAPClient for the active speaker's group coordinator.
    var activeClient: SOAPClient? {
        guard let device = deviceManager.activeDevice,
              let ip = deviceManager.coordinatorIP(for: device.uuid) else { return nil }
        return SOAPClient(host: ip)
    }

    var activeController: PlaybackController? {
        guard let client = activeClient else { return nil }
        return PlaybackController(client: client)
    }

    func startDiscovery() async {
        // Restore cached speakers immediately
        let cached = settings.loadCachedSpeakers()
        if !cached.isEmpty, let savedUUID = settings.activeDeviceUUID {
            deviceManager.setActiveDevice(uuid: savedUUID)
        }

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

        // Refresh playback state
        await refreshPlayback()
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
        Task { await refreshPlayback() }
    }
}
