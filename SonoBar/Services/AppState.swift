// SonoBar/Services/AppState.swift
import AppKit
import SwiftUI
import SonoBarKit
#if canImport(Darwin)
import Darwin
#endif

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
    private var subscriptionIDs: [SonosService: String] = [:]
    private var isDiscovering = false

    var playbackState = PlaybackState(transportState: .stopped, volume: 0, isMuted: false)
    var albumArtImage: NSImage? = nil
    var isLoading = true
    private(set) var activeController: PlaybackController?
    private let artworkCache = ArtworkCache()
    /// Playback summary keyed by device UUID, populated for all rooms.
    var roomStates: [String: RoomSummary] = [:]
    let mediaKeyController = MediaKeyController()
    var recentItems: [ContentItem] = []
    private var lastMediaURI: String?
    private static let maxRecents = 50
    private static let recentsKey = "recentItems"

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
        loadRecents()
        await refreshPlayback()
        await refreshAllRooms()
        await startEventListener()

        mediaKeyController.onPlayPause = { [weak self] in
            guard let self else { return }
            Task {
                if self.playbackState.transportState == .playing {
                    try? await self.activeController?.pause()
                } else {
                    try? await self.activeController?.play()
                }
                await self.refreshPlayback()
            }
        }
        mediaKeyController.onNext = { [weak self] in
            guard let self else { return }
            Task {
                try? await self.activeController?.next()
                await self.refreshPlayback()
            }
        }
        mediaKeyController.onPrevious = { [weak self] in
            guard let self else { return }
            Task {
                try? await self.activeController?.previous()
                await self.refreshPlayback()
            }
        }
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
        mediaKeyController.updateNowPlaying(
            track: currentTrack,
            transportState: transportState
        )

        await loadAlbumArt()

        // Track recents: when the media source changes, record it
        if transportState == .playing || transportState == .pausedPlayback {
            if let mediaInfo = try? await controller.getMediaInfo(),
               !mediaInfo.uri.isEmpty,
               mediaInfo.uri != lastMediaURI {
                lastMediaURI = mediaInfo.uri

                var recentURI = mediaInfo.uri
                var recentDIDL = mediaInfo.metadata

                // For queue-based playback (Audible, Plex, etc.), get the original
                // content URI from EnqueuedTransportURI so we can replay it
                if !Self.isReplayableURI(mediaInfo.uri) {
                    if let enqueued = try? await controller.getEnqueuedTransportURI(),
                       Self.isReplayableURI(enqueued.uri) {
                        recentURI = enqueued.uri
                        recentDIDL = enqueued.metadata
                        #if DEBUG
                        print("[Recents] Queue content — using enqueued URI: \(enqueued.uri)")
                        #endif
                    } else {
                        #if DEBUG
                        print("[Recents] Skipping non-replayable URI: \(mediaInfo.uri)")
                        #endif
                        return
                    }
                }

                let item = ContentItem(
                    id: recentURI,
                    title: currentTrack?.title ?? "Unknown",
                    albumArtURI: currentTrack?.albumArtURI,
                    resourceURI: recentURI,
                    rawDIDL: recentDIDL,
                    itemClass: "object.item.audioItem",
                    description: currentTrack?.artist
                )
                addRecent(item)
            }
        }
    }

    func selectRoom(uuid: String) {
        deviceManager.setActiveDevice(uuid: uuid)
        settings.activeDeviceUUID = uuid
        updateActiveController()
        stopEventListener()
        Task {
            await refreshPlayback()
            await startEventListener()
        }
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

    func loadAlbumArt() async {
        guard let albumArtURI = playbackState.currentTrack?.albumArtURI,
              !albumArtURI.isEmpty else {
            albumArtImage = nil
            return
        }

        // Absolute URLs (from Spotify, Tidal, etc.) are used directly;
        // relative paths (from local library, Sonos radio) are prefixed with the speaker IP.
        let fullURL: String
        if albumArtURI.hasPrefix("http://") || albumArtURI.hasPrefix("https://") {
            fullURL = albumArtURI
        } else {
            guard let device = deviceManager.activeDevice,
                  let ip = deviceManager.coordinatorIP(for: device.uuid) else {
                albumArtImage = nil
                return
            }
            fullURL = "http://\(ip):1400\(albumArtURI)"
        }

        if let cached = artworkCache.get(for: fullURL) {
            albumArtImage = cached
            return
        }

        guard let url = URL(string: fullURL),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            albumArtImage = nil
            return
        }

        artworkCache.set(data, for: fullURL)
        albumArtImage = NSImage(data: data)
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
    var isBrowseLoading = false

    /// Favorites and Playlists are system-wide — any speaker can serve them.
    /// Try the active speaker's coordinator first, fall back to any reachable device.
    private func browseSystemWide(
        _ operation: (SOAPClient) async throws -> [ContentItem]
    ) async {
        contentError = nil
        contentItems = []
        isBrowseLoading = true
        defer { isBrowseLoading = false }

        // Build candidate IPs: coordinator first, then all known devices
        var candidateIPs: [String] = []
        if let client = activeClient { candidateIPs.append(client.host) }
        for device in deviceManager.devices where !device.ip.isEmpty && !candidateIPs.contains(device.ip) {
            candidateIPs.append(device.ip)
        }
        guard !candidateIPs.isEmpty else {
            contentError = "No speaker selected"
            return
        }

        for ip in candidateIPs {
            do {
                contentItems = try await operation(SOAPClient(host: ip))
                return
            } catch {
                continue
            }
        }
        contentError = "No speaker reachable"
    }

    func browseFavorites() async {
        await browseSystemWide { try await ContentBrowser.browseFavorites(client: $0) }
    }

    func browsePlaylists() async {
        await browseSystemWide { try await ContentBrowser.browsePlaylists(client: $0) }
    }

    func browseQueue() async {
        contentError = nil
        contentItems = []
        isBrowseLoading = true
        defer { isBrowseLoading = false }
        guard let client = activeClient else {
            contentError = "No speaker selected"
            return
        }
        do {
            contentItems = try await ContentBrowser.browseQueue(client: client)
        } catch {
            contentError = "Queue: \(error.localizedDescription)"
        }
    }

    func playItem(_ item: ContentItem) async {
        guard let client = activeClient else { return }
        #if DEBUG
        print("[PlayItem] URI: \(item.resourceURI)")
        print("[PlayItem] DIDL length: \(item.rawDIDL.count), empty: \(item.rawDIDL.isEmpty)")
        print("[PlayItem] DIDL: \(String(item.rawDIDL.prefix(200)))")
        #endif
        do {
            try await ContentBrowser.playItem(client: client, item: item)
            await refreshPlayback()
        } catch {
            #if DEBUG
            print("[PlayItem] Failed with metadata, retrying without: \(error)")
            #endif
            // Retry without metadata — some URIs work without it
            do {
                let noMetadata = ContentItem(
                    id: item.id, title: item.title, albumArtURI: item.albumArtURI,
                    resourceURI: item.resourceURI, rawDIDL: "",
                    itemClass: item.itemClass, description: item.description
                )
                try await ContentBrowser.playItem(client: client, item: noMetadata)
                await refreshPlayback()
            } catch {
                #if DEBUG
                print("[PlayItem] Also failed without metadata: \(error)")
                #endif
                contentError = "Play failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Alarms & Sleep Timer

    var alarms: [SonosAlarm] = []
    var sleepTimerRemaining: String? = nil
    /// Computed end date for local countdown — set from API remaining time.
    var sleepTimerEndDate: Date? = nil

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
        // Set end date immediately — don't rely on a second SOAP round-trip
        sleepTimerEndDate = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerRemaining = String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
    }

    func cancelSleepTimer() async {
        guard let client = activeClient else { return }
        try? await SleepTimerController.cancelSleepTimer(client: client)
        sleepTimerRemaining = nil
        sleepTimerEndDate = nil
    }

    func refreshSleepTimer() async {
        guard let client = activeClient else { return }
        do {
            let remaining = try await SleepTimerController.getRemainingTime(client: client)
            sleepTimerRemaining = remaining
            if let remaining {
                let seconds = parseSleepTime(remaining)
                sleepTimerEndDate = seconds > 0 ? Date.now.addingTimeInterval(TimeInterval(seconds)) : nil
            } else {
                // API succeeded but no timer active
                sleepTimerEndDate = nil
            }
        } catch {
            // API call failed — keep existing values rather than clearing
        }
    }

    /// Returns true if the URI can be replayed via SetAVTransportURI.
    /// Queue refs, group joins, line-in, and TV audio can't be replayed.
    private static func isReplayableURI(_ uri: String) -> Bool {
        let nonReplayable = [
            "x-rincon-queue:",      // queue reference — not a content URI
            "x-rincon:",            // group join URI
            "x-rincon-stream:",     // line-in audio
            "x-sonos-htastream:",   // TV/HDMI audio
        ]
        return !nonReplayable.contains { uri.hasPrefix($0) }
    }

    /// Parses "HH:MM:SS" into total seconds.
    private func parseSleepTime(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }

    // MARK: - Recents

    private func addRecent(_ item: ContentItem) {
        // Remove existing entry with same URI, then prepend
        recentItems.removeAll { $0.resourceURI == item.resourceURI }
        recentItems.insert(item, at: 0)
        if recentItems.count > Self.maxRecents {
            recentItems = Array(recentItems.prefix(Self.maxRecents))
        }
        saveRecents()
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(recentItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentsKey)
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentsKey),
              let items = try? JSONDecoder().decode([ContentItem].self, from: data) else { return }
        // Filter out any non-replayable URIs saved from before the filter was added
        recentItems = items.filter { Self.isReplayableURI($0.resourceURI) }
    }

    // MARK: - UPnP Event Subscriptions

    private func startEventListener() async {
        guard let device = deviceManager.activeDevice,
              let speakerIP = deviceManager.coordinatorIP(for: device.uuid) else { return }

        let listener = UPnPEventListener()
        self.eventListener = listener

        do {
            try await listener.start { [weak self] service, properties in
                Task { @MainActor [weak self] in
                    self?.handleEvent(service: service, properties: properties)
                }
            }
        } catch {
            return
        }

        guard let port = listener.port,
              let localIP = getLocalIP() else { return }

        let services: [SonosService] = [.avTransport, .renderingControl]
        for service in services {
            let callbackURL = "http://\(localIP):\(port)\(UPnPEventListener.callbackPath(for: service))"
            let request = UPnPSubscription.buildSubscribeRequest(
                speakerHost: speakerIP,
                service: service,
                callbackURL: callbackURL
            )
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               let sid = httpResponse.value(forHTTPHeaderField: "SID") {
                subscriptionIDs[service] = sid
            }
        }
    }

    private func handleEvent(service: SonosService, properties: [String: String]) {
        Task {
            await refreshPlayback()
        }
    }

    private func stopEventListener() {
        guard let device = deviceManager.activeDevice,
              let speakerIP = deviceManager.coordinatorIP(for: device.uuid) else {
            eventListener?.stop()
            eventListener = nil
            subscriptionIDs.removeAll()
            return
        }

        for (service, sid) in subscriptionIDs {
            let request = UPnPSubscription.buildUnsubscribeRequest(
                speakerHost: speakerIP,
                service: service,
                sid: sid
            )
            Task { _ = try? await URLSession.shared.data(for: request) }
        }

        eventListener?.stop()
        eventListener = nil
        subscriptionIDs.removeAll()
    }

    private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee
            guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: addr.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                         &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            return String(cString: hostname)
        }
        return nil
    }
}
