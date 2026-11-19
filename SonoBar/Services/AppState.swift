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
    let trackURI: String?
    let albumArtURI: String?
    let mediaURI: String?
    let mediaDIDL: String?
}

@MainActor
@Observable
final class AppState {
    let deviceManager = DeviceManager()
    private let ssdp = SSDPDiscovery()
    private let settings = SettingsStore()
    private var eventListener: UPnPEventListener?
    private var eventSpeakerIP: String?
    private var subscriptionIDs: [SonosService: String] = [:]
    private var isDiscovering = false

    var playbackState = PlaybackState(transportState: .stopped, volume: 0, isMuted: false)
    var albumArtImage: NSImage? = nil
    var isLoading = true
    private(set) var activeController: PlaybackController?
    private(set) var activeRoomController: PlaybackController?
    private var refreshingController: PlaybackController?
    private var playbackRefreshPending = false
    private let artworkCache = ArtworkCache.shared
    /// Playback summary keyed by device UUID, populated for all rooms.
    var roomStates: [String: RoomSummary] = [:]
    let mediaKeyController = MediaKeyController()
    var recentItems: [ContentItem] = []
    private var lastMediaURI: String?
    private var lastTrackURI: String?
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
        initPlexIfConfigured()
        initAudibleIfConfigured()
        await refreshPlayback()
        await refreshAllRooms()
        if let controller = activeController {
            await startEventListener(for: controller)
        }

        mediaKeyController.onPlayPause = { [weak self] in
            Task { await self?.togglePlayback() }
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

        await discoverAppleMusicCredentials()
        if appleMusicCredentials != nil {
            appleMusicAuthStatus = await musicDiscovery.requestAuthorization()
        }
    }

    func refreshPlayback() async {
        guard let controller = activeController, let roomController = activeRoomController else { return }
        if refreshingController === controller {
            playbackRefreshPending = true
            return
        }
        refreshingController = controller
        defer {
            if refreshingController === controller { refreshingController = nil }
        }
        repeat {
            playbackRefreshPending = false
            await refreshPlayback(controller: controller, roomController: roomController)
        } while activeController === controller && playbackRefreshPending
    }

    func togglePlayback() async {
        guard let controller = activeController else { return }
        let room = deviceManager.activeDevice.flatMap { deviceManager.group(for: $0.uuid)?.coordinatorUUID }
        let monitor = room.flatMap { plexProgressRooms[$0]?.monitor }
        do {
            if playbackState.transportState == .playing {
                try await controller.pause()
            } else {
                try await controller.play()
            }
            if let monitor { Task { await monitor.sample() } }
        } catch {
            // Refresh from Sonos to keep the control in sync if the command failed.
        }
        await refreshPlayback()
    }

    private func refreshPlayback(controller: PlaybackController, roomController: PlaybackController) async {
        async let transportRequest = try? controller.getTransportState()
        async let trackRequest = try? controller.getPositionInfo()
        async let volumeRequest = try? roomController.getVolume()
        async let muteRequest = try? roomController.getMute()
        let (transport, currentTrack, roomVolume, roomMuted) = await (
            transportRequest, trackRequest, volumeRequest, muteRequest
        )
        guard activeController === controller else { return }
        let transportState = transport ?? .stopped
        playbackState = PlaybackState(
            transportState: transportState,
            volume: roomVolume ?? playbackState.volume,
            isMuted: roomMuted ?? playbackState.isMuted,
            currentTrack: currentTrack
        )
        mediaKeyController.updateNowPlaying(
            track: currentTrack,
            transportState: transportState
        )

        await loadAlbumArt(for: controller)
        guard activeController === controller else { return }

        // Track recents: when the media source changes, record it.
        // Check both media URI and track URI — for queue-based playback (Plex, Audible)
        // the media URI stays the same (x-rincon-queue:...) even when content changes.
        let currentTrackURI = currentTrack?.uri
        if transportState == .playing || transportState == .pausedPlayback {
            if let mediaInfo = try? await controller.getMediaInfo(),
               activeController === controller,
               !mediaInfo.uri.isEmpty,
               (mediaInfo.uri != lastMediaURI || currentTrackURI != lastTrackURI) {
                lastMediaURI = mediaInfo.uri
                lastTrackURI = currentTrackURI

                var recentURI = mediaInfo.uri
                var recentDIDL = mediaInfo.metadata

                // For queue-based playback (Audible, Plex, etc.), get the original
                // content URI from EnqueuedTransportURI so we can replay it
                if !Self.isReplayableURI(mediaInfo.uri) {
                    if let enqueued = try? await controller.getEnqueuedTransportURI(),
                       activeController === controller,
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
        guard deviceManager.activeDevice?.uuid != uuid,
              deviceManager.devices.contains(where: { $0.uuid == uuid }) else { return }
        stopEventListener()
        deviceManager.setActiveDevice(uuid: uuid)
        settings.activeDeviceUUID = uuid
        updateActiveController()
        playbackState = PlaybackState(transportState: .stopped, volume: 0, isMuted: false)
        albumArtImage = nil
        contentItems = []
        contentError = nil
        isBrowseLoading = false
        sleepTimerRemaining = nil
        sleepTimerEndDate = nil
        lastMediaURI = nil
        lastTrackURI = nil
        mediaKeyController.updateNowPlaying(track: nil, transportState: .stopped)
        let controller = activeController
        Task {
            guard let controller, activeController === controller else { return }
            async let playback: Void = refreshPlayback()
            async let timer: Void = refreshSleepTimer()
            await startEventListener(for: controller)
            _ = await (playback, timer)
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
                    let media = try? await controller.getMediaInfo()
                    let summary = RoomSummary(
                        transportState: transport,
                        trackTitle: track?.title,
                        trackArtist: track?.artist,
                        trackURI: track?.uri,
                        albumArtURI: track?.albumArtURI,
                        mediaURI: media?.uri,
                        mediaDIDL: media?.metadata
                    )
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

            // Capture content loaded on all rooms as recents.
            // Includes playing, paused, AND stopped — stopped content is still
            // loaded on the speaker and will resume if you hit play.
            // Uses the media URI (album-level) when replayable — covers
            // Audible, Apple Music, Spotify, radio, and other services.
            // Plex queue content filtered out (x-rincon-queue:) — handled separately.
            for (_, summary) in coordinatorSummaries {
                guard summary.transportState != .transitioning,
                      summary.transportState != .noMediaPresent,
                      let title = summary.trackTitle, !title.isEmpty else { continue }

                // Prefer the media URI (album/station level) over track URI
                let uri: String
                let didl: String
                if let mediaURI = summary.mediaURI, !mediaURI.isEmpty, Self.isReplayableURI(mediaURI) {
                    uri = mediaURI
                    didl = summary.mediaDIDL ?? ""
                } else if let trackURI = summary.trackURI, !trackURI.isEmpty, Self.isStreamURI(trackURI) {
                    // Fallback to track URI for streams where media URI isn't useful
                    uri = trackURI
                    didl = ""
                } else {
                    continue
                }

                let item = ContentItem(
                    id: uri,
                    title: title,
                    albumArtURI: summary.albumArtURI,
                    resourceURI: uri,
                    rawDIDL: didl,
                    itemClass: "object.item.audioItem",
                    description: summary.trackArtist
                )
                addRecent(item)
            }

            // Discover Audible Sonos service params if not yet found
            if sonosAudibleParams == nil {
                if let params = SonosAudibleParams.discover(from: newStates) {
                    sonosAudibleParams = params
                    params.save()
                }
            }
        }
    }

    private func loadAlbumArt(for controller: PlaybackController) async {
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

        let image = await artworkCache.image(for: fullURL)
        guard activeController === controller else { return }
        albumArtImage = image
    }

    private func updateActiveController() {
        guard let device = deviceManager.activeDevice,
              let ip = deviceManager.coordinatorIP(for: device.uuid) else {
            activeController = nil
            activeRoomController = nil
            return
        }
        let controller = PlaybackController(client: SOAPClient(host: ip))
        activeController = controller
        activeRoomController = device.ip == ip
            ? controller
            : PlaybackController(client: SOAPClient(host: device.ip))
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
        let controller = activeController
        contentError = nil
        contentItems = []
        isBrowseLoading = true
        defer {
            if activeController === controller { isBrowseLoading = false }
        }
        guard let client = activeClient else {
            contentError = "No speaker selected"
            return
        }
        do {
            let items = try await ContentBrowser.browseQueue(client: client)
            guard activeController === controller else { return }
            contentItems = items
        } catch {
            guard activeController === controller else { return }
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
        guard let client = activeClient, let controller = activeController else { return }
        guard (try? await SleepTimerController.setSleepTimer(client: client, minutes: minutes)) != nil,
              activeController === controller else { return }
        // Set end date immediately — don't rely on a second SOAP round-trip
        sleepTimerEndDate = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerRemaining = String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
    }

    func cancelSleepTimer() async {
        guard let client = activeClient, let controller = activeController else { return }
        guard (try? await SleepTimerController.cancelSleepTimer(client: client)) != nil,
              activeController === controller else { return }
        sleepTimerRemaining = nil
        sleepTimerEndDate = nil
    }

    func refreshSleepTimer() async {
        guard let client = activeClient, let controller = activeController else { return }
        do {
            let remaining = try await SleepTimerController.getRemainingTime(client: client)
            guard activeController === controller else { return }
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

    /// Returns true if the URI is a stream/radio where the track URI is the replayable source.
    /// Used for room-level recents capture (vs individual tracks from queues).
    private static func isStreamURI(_ uri: String) -> Bool {
        let streamPrefixes = [
            "x-sonosapi-stream:",       // Sonos service streams (BBC Sounds, etc.)
            "x-sonosapi-hls-static:",   // HLS streams
            "x-sonosapi-radio:",        // Sonos radio
            "x-rincon-mp3radio:",       // MP3 radio streams
            "aac:",                     // AAC radio streams
            "hls:",                     // HLS radio
        ]
        return streamPrefixes.contains { uri.hasPrefix($0) }
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

    private func startEventListener(for controller: PlaybackController) async {
        guard activeController === controller,
              let device = deviceManager.activeDevice,
              let speakerIP = deviceManager.coordinatorIP(for: device.uuid) else { return }

        stopEventListener()
        let listener = UPnPEventListener()
        eventListener = listener
        eventSpeakerIP = speakerIP

        do {
            try await listener.start { [weak self, weak listener] service, properties in
                let paused = service == .avTransport && properties.values.contains { $0.contains("PAUSED_PLAYBACK") }
                Task { @MainActor [weak self, weak listener] in
                    guard let self, let listener, self.eventListener === listener else { return }
                    if paused, let room = self.deviceManager.group(for: device.uuid)?.coordinatorUUID,
                       let monitor = self.plexProgressRooms[room]?.monitor {
                        Task { await monitor.sample() }
                    }
                    await self.refreshPlayback()
                }
            }
        } catch {
            if eventListener === listener { stopEventListener() }
            return
        }

        guard eventListener === listener else {
            listener.stop()
            return
        }
        guard let port = listener.port, let localIP = getLocalIP() else {
            stopEventListener()
            return
        }

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
                guard eventListener === listener else {
                    unsubscribe(speakerIP: speakerIP, service: service, sid: sid)
                    return
                }
                subscriptionIDs[service] = sid
            }
            guard eventListener === listener else { return }
        }
    }

    private func unsubscribe(speakerIP: String, service: SonosService, sid: String) {
        let request = UPnPSubscription.buildUnsubscribeRequest(speakerHost: speakerIP, service: service, sid: sid)
        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    private func stopEventListener() {
        if let speakerIP = eventSpeakerIP {
            for (service, sid) in subscriptionIDs {
                unsubscribe(speakerIP: speakerIP, service: service, sid: sid)
            }
        }

        eventListener?.stop()
        eventListener = nil
        eventSpeakerIP = nil
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

    // MARK: - Plex Integration

    enum PlexConnection: Equatable {
        case checking
        case connected
        case signInRequired
        case failed(String)
    }

    private(set) var plexClient: PlexClient?
    private(set) var plexConnection: PlexConnection = .checking
    private(set) var plexLibraries: [PlexLibrary] = []
    private(set) var plexOnDeck: [PlexTrack] = []
    private(set) var plexOnDeckError: String?
    var plexError: String?
    private(set) var plexQueueMessage: String?
    private(set) var isUpdatingPlexQueue = false
    private struct PlexProgressRoom {
        let monitor: PlexProgressMonitor
        let task: Task<Void, Never>
    }
    @ObservationIgnored private var plexProgressRooms: [String: PlexProgressRoom] = [:]

    private static let plexHostKey = "plexServerIP"

    func connectPlex(host: String, token: String) throws {
        try PlexKeychain.setToken(token)
        UserDefaults.standard.set(host, forKey: Self.plexHostKey)
        stopPlexProgressMonitoring()
        plexClient = PlexClient(host: host, token: token)
        plexConnection = .checking
        plexError = nil
    }

    func disconnectPlex() {
        UserDefaults.standard.removeObject(forKey: Self.plexHostKey)
        PlexKeychain.deleteToken()
        plexClient = nil
        plexConnection = .checking
        plexLibraries = []
        plexOnDeck = []
        plexOnDeckError = nil
        plexError = nil
        plexQueueMessage = nil
        stopPlexProgressMonitoring()
    }

    func initPlexIfConfigured() {
        guard plexClient == nil,
              let host = UserDefaults.standard.string(forKey: Self.plexHostKey),
              let token = PlexKeychain.getToken() else { return }
        plexClient = PlexClient(host: host, token: token)
    }

    func requirePlexSignIn(for client: PlexClient) {
        guard plexClient === client else { return }
        stopPlexProgressMonitoring()
        plexConnection = .signInRequired
        plexLibraries = []
        plexOnDeck = []
        plexOnDeckError = nil
        plexError = nil
    }

    func loadPlexHome() async {
        guard let client = plexClient else { return }
        if plexConnection != .connected {
            plexConnection = .checking
        }

        let libraries: [PlexLibrary]
        do {
            libraries = try await client.getLibraries().filter { $0.type == "artist" }
        } catch {
            guard !Task.isCancelled, plexClient === client else { return }
            if error as? PlexError == .unauthorized {
                requirePlexSignIn(for: client)
            } else {
                plexConnection = .failed(error.localizedDescription)
            }
            return
        }
        guard !Task.isCancelled, plexClient === client, plexConnection != .signInRequired else { return }
        plexLibraries = libraries
        plexConnection = .connected
        plexOnDeckError = nil

        var tracks: [PlexTrack] = []
        var onDeckError: String?
        for library in libraries {
            do {
                tracks.append(contentsOf: try await client.getOnDeck(sectionId: library.id))
            } catch {
                onDeckError = "Couldn’t load Continue Listening. \(error.localizedDescription)"
            }
            guard !Task.isCancelled, plexClient === client, plexConnection == .connected else { return }
        }
        plexOnDeck = tracks.sorted {
            ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast)
        }
        plexOnDeckError = onDeckError
    }

    // MARK: - Plex Playback

    enum PlexQueueAction {
        case playNow(startIndex: Int = 0, offsetSeconds: Int = 0)
        case playNext
        case addToQueue
    }

    func resumePlexTrack(_ track: PlexTrack) async {
        await updatePlexQueue(action: .playNow(offsetSeconds: track.viewOffset / 1000)) { client in
            try await client.getResumeTracks(startingAt: track)
        }
    }

    func queuePlexTracks(_ tracks: [PlexTrack], action: PlexQueueAction) async {
        await updatePlexQueue(action: action) { _ in tracks }
    }

    private func updatePlexQueue(
        action: PlexQueueAction, loadTracks: (PlexClient) async throws -> [PlexTrack]
    ) async {
        guard !isUpdatingPlexQueue, plexConnection != .signInRequired, let client = plexClient else { return }
        plexError = nil
        plexQueueMessage = nil
        guard let controller = activeController,
              let device = deviceManager.activeDevice,
              let group = deviceManager.group(for: device.uuid) else {
            plexError = "Choose a Sonos room before playing Plex."
            return
        }
        isUpdatingPlexQueue = true
        defer { isUpdatingPlexQueue = false }

        let tracks: [PlexTrack]
        do {
            tracks = try await loadTracks(client)
        } catch {
            guard plexClient === client, !Task.isCancelled else { return }
            if error as? PlexError == .unauthorized {
                requirePlexSignIn(for: client)
            } else {
                plexError = "Couldn't load the remaining chapters. \(error.localizedDescription)"
            }
            return
        }
        guard plexClient === client, plexConnection != .signInRequired, !Task.isCancelled, !tracks.isEmpty else { return }
        let room = group.coordinatorUUID
        let monitor = plexProgressMonitor(room: room, controller: controller, client: client)
        await monitor.beginQueueUpdate()
        await enqueuePlexTracks(
            tracks, action: action, client: client, controller: controller,
            room: room, roomName: device.roomName, monitor: monitor
        )
        await monitor.finishQueueUpdate()
        Task { await monitor.sample() }
    }

    private func enqueuePlexTracks(
        _ tracks: [PlexTrack], action: PlexQueueAction, client: PlexClient, controller: PlaybackController,
        room: String, roomName: String, monitor: PlexProgressMonitor
    ) async {
        let queueURI = "x-rincon-queue:\(room)#0"
        let audioURLs = tracks.compactMap { client.audioURL(partKey: $0.partKey)?.absoluteString }
        guard audioURLs.count == tracks.count else {
            plexError = "Plex returned an invalid audio address."
            return
        }

        var addedPositions: [Int] = []
        do {
            var insertPosition = 0
            let playNext: Bool
            switch action {
            case .playNext: playNext = true
            default: playNext = false
            }
            switch action {
            case .addToQueue:
                break
            case .playNow, .playNext:
                let media = try await controller.getMediaInfo()
                if media?.uri == queueURI {
                    guard let currentTrack = try await controller.getPositionInfo() else {
                        plexError = "Couldn't find the current track in \(roomName)'s queue."
                        return
                    }
                    insertPosition = currentTrack.trackNumber + 1
                } else {
                    insertPosition = 1
                }
            }

            for (track, uri) in zip(tracks, audioURLs) {
                guard plexClient === client, plexConnection != .signInRequired, !Task.isCancelled else { return }
                let position = try await controller.addToQueue(
                    uri: uri, metadata: plexDIDL(track: track), position: insertPosition,
                    enqueueAsNext: playNext && addedPositions.isEmpty
                )
                addedPositions.append(position)
                guard plexClient === client, plexConnection != .signInRequired else { return }
                await monitor.recordQueuedTrack(id: track.id, uri: uri)
                if insertPosition > 0 { insertPosition = max(position, insertPosition) + 1 }
            }

            if case .playNow(let startIndex, let offsetSeconds) = action {
                guard addedPositions.indices.contains(startIndex), addedPositions[startIndex] > 0 else {
                    plexError = "Added to \(roomName)'s queue. Sonos didn't return a track position to play."
                    return
                }
                try await controller.playQueuedTrack(addedPositions[startIndex], queueURI: queueURI)
                addPlexRecent(track: tracks[startIndex])
                if offsetSeconds > 0 {
                    guard try await waitForPlaying(on: controller) else {
                        plexError = "Playback didn't start in time to resume at the saved position."
                        return
                    }
                    let target = String(format: "%d:%02d:%02d", offsetSeconds / 3600,
                                        (offsetSeconds % 3600) / 60, offsetSeconds % 60)
                    try await controller.seek(to: target)
                }
                if activeController === controller { await refreshPlayback() }
            } else {
                let count = addedPositions.count
                plexQueueMessage = "Added \(count) \(count == 1 ? "track" : "tracks") to \(roomName)."
            }
        } catch {
            guard plexClient === client, !Task.isCancelled else { return }
            if addedPositions.count == tracks.count {
                plexError = "Added to \(roomName)'s queue, but playback couldn't start at the requested position."
            } else if addedPositions.isEmpty {
                plexError = "Couldn't add tracks to \(roomName)'s queue. \(error.localizedDescription)"
            } else {
                plexError = "Only \(addedPositions.count) of \(tracks.count) tracks were added to \(roomName)'s queue."
            }
        }
    }

    /// Adds a Plex track to recents with its audio URL as the replayable URI.
    private func addPlexRecent(track: PlexTrack) {
        guard let client = plexClient,
              let audioURL = client.audioURL(partKey: track.partKey) else { return }
        let artURL = track.thumbPath.flatMap { client.thumbURL(path: $0)?.absoluteString }
        let item = ContentItem(
            id: audioURL.absoluteString,
            title: track.albumTitle.isEmpty ? track.title : track.albumTitle,
            albumArtURI: artURL,
            resourceURI: audioURL.absoluteString,
            rawDIDL: plexDIDL(track: track),
            itemClass: "object.item.audioItem",
            description: track.artistName.isEmpty ? nil : track.artistName
        )
        addRecent(item)
    }

    private func waitForPlaying(on controller: PlaybackController) async throws -> Bool {
        for _ in 0..<20 {
            if try await controller.getTransportState() == .playing {
                return true
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func plexDIDL(track: PlexTrack) -> String {
        let title = xmlEscape(track.title)
        let creator = xmlEscape(track.artistName)
        let album = xmlEscape(track.albumTitle)
        var artTag = ""
        if let thumbPath = track.thumbPath, let url = plexClient?.thumbURL(path: thumbPath) {
            artTag = "<upnp:albumArtURI>\(xmlEscape(url.absoluteString))</upnp:albumArtURI>"
        }
        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item><dc:title>\(title)</dc:title>\
        <dc:creator>\(creator)</dc:creator>\
        <upnp:album>\(album)</upnp:album>\
        \(artTag)\
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>\
        </item></DIDL-Lite>
        """
    }

    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func plexProgressMonitor(
        room: String, controller: PlaybackController, client: PlexClient
    ) -> PlexProgressMonitor {
        if let existing = plexProgressRooms[room] { return existing.monitor }
        let monitor = PlexProgressMonitor(controller: controller, client: client, coordinatorUUID: room)
        let task = Task { await monitor.run() }
        plexProgressRooms[room] = PlexProgressRoom(monitor: monitor, task: task)
        return monitor
    }

    private func stopPlexProgressMonitoring() {
        for room in plexProgressRooms.values {
            room.task.cancel()
            Task { await room.monitor.stop() }
        }
        plexProgressRooms.removeAll()
    }

    // MARK: - Audible Integration

    private(set) var audibleClient: AudibleClient?
    var audibleBooks: [AudibleBook] = []
    var audibleChapters: [AudibleChapter] = []
    var audibleEpisodes: [AudibleBook] = []
    var audibleOnDeck: [(book: AudibleBook, positionMs: Int)] = []
    var audibleError: String?
    var isAudibleLoading = false
    private(set) var sonosAudibleParams: SonosAudibleParams?

    func connectAudible(marketplace: String, adpToken: String, privateKeyPEM: String,
                        accessToken: String, refreshToken: String, deviceSerial: String) {
        AudibleKeychain.setAll(
            accessToken: accessToken,
            refreshToken: refreshToken,
            adpToken: adpToken,
            privateKeyPEM: privateKeyPEM,
            deviceSerial: deviceSerial
        )

        audibleClient = AudibleClient(
            marketplace: marketplace,
            adpToken: adpToken,
            privateKeyPEM: privateKeyPEM,
            accessToken: accessToken
        )
        audibleError = nil

        // Auto-discover Sonos Audible params if not already set
        Task {
            if sonosAudibleParams == nil, let client = activeClient {
                if let params = await SonosAudibleParams.discoverFromMusicServices(client: client) {
                    sonosAudibleParams = params
                    params.save()
                }
            }
            await loadAudibleLibrary()
        }
    }

    func discoverAudibleParams() async {
        guard let client = activeClient else { return }
        if let params = await SonosAudibleParams.discoverFromMusicServices(client: client) {
            sonosAudibleParams = params
            params.save()
        }
    }

    func disconnectAudible() {
        AudibleKeychain.deleteAll()
        SonosAudibleParams.clear()
        audibleClient = nil
        audibleBooks = []
        audibleChapters = []
        audibleEpisodes = []
        audibleOnDeck = []
        audibleError = nil
        isAudibleLoading = false
        sonosAudibleParams = nil
    }

    func initAudibleIfConfigured() {
        guard let adpToken = AudibleKeychain.getAdpToken(),
              let privateKey = AudibleKeychain.getPrivateKeyPEM(),
              let accessToken = AudibleKeychain.getAccessToken() else { return }

        // Derive marketplace from the auth domain
        let marketplace = String(AudibleAuth.domain.dropFirst("amazon.".count))

        audibleClient = AudibleClient(
            marketplace: marketplace,
            adpToken: adpToken,
            privateKeyPEM: privateKey,
            accessToken: accessToken
        )

        // Load cached Sonos params, or discover from MusicServices
        sonosAudibleParams = SonosAudibleParams.load()

        Task {
            if sonosAudibleParams == nil, let client = activeClient {
                if let params = await SonosAudibleParams.discoverFromMusicServices(client: client) {
                    sonosAudibleParams = params
                    params.save()
                }
            }
            await loadAudibleLibrary()
        }
    }

    /// Attempts to refresh the Audible access token using the stored refresh token.
    /// On success, recreates the audibleClient with the new token.
    private func refreshAudibleToken() async -> Bool {
        guard let refreshToken = AudibleKeychain.getRefreshToken() else { return false }
        let request = AudibleAuth.buildTokenRefreshRequest(refreshToken: refreshToken)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else {
                #if DEBUG
                print("[AudibleAuth] Token refresh failed")
                #endif
                return false
            }
            AudibleKeychain.setAccessToken(newAccessToken)
            // Recreate client with new token
            if let adpToken = AudibleKeychain.getAdpToken(),
               let privateKey = AudibleKeychain.getPrivateKeyPEM() {
                let marketplace = String(AudibleAuth.domain.dropFirst("amazon.".count))
                audibleClient = AudibleClient(
                    marketplace: marketplace,
                    adpToken: adpToken,
                    privateKeyPEM: privateKey,
                    accessToken: newAccessToken
                )
            }
            #if DEBUG
            print("[AudibleAuth] Token refreshed successfully")
            #endif
            return true
        } catch {
            #if DEBUG
            print("[AudibleAuth] Token refresh error: \(error)")
            #endif
            return false
        }
    }

    func loadAudibleLibrary() async {
        guard audibleClient != nil else {
            #if DEBUG
            print("[Audible] loadAudibleLibrary: no client")
            #endif
            return
        }
        isAudibleLoading = true
        defer { isAudibleLoading = false }
        do {
            #if DEBUG
            print("[Audible] Loading library...")
            #endif
            audibleBooks = try await audibleClient!.getLibrary()
            #if DEBUG
            print("[Audible] Library loaded: \(audibleBooks.count) books")
            #endif
            audibleError = nil
        } catch AudibleError.unauthorized {
            #if DEBUG
            print("[Audible] Got 401, attempting token refresh...")
            #endif
            if await refreshAudibleToken(), let client = audibleClient {
                do {
                    audibleBooks = try await client.getLibrary()
                    audibleError = nil
                    #if DEBUG
                    print("[Audible] Library loaded after refresh: \(audibleBooks.count) books")
                    #endif
                    return
                } catch {
                    #if DEBUG
                    print("[Audible] Library still failed after refresh: \(error)")
                    #endif
                }
            }
            audibleError = "Session expired. Try disconnecting and signing in again."
        } catch {
            #if DEBUG
            print("[Audible] Library load error: \(error)")
            #endif
            audibleError = "Failed to load library: \(error.localizedDescription)"
        }
    }

    func loadAudibleChapters(asin: String) async {
        guard let client = audibleClient else { return }
        isAudibleLoading = true
        defer { isAudibleLoading = false }
        do {
            audibleChapters = try await client.getChapters(asin: asin)
            audibleError = nil
        } catch {
            audibleError = "Failed to load chapters: \(error.localizedDescription)"
        }
    }

    func loadAudibleEpisodes(parentAsin: String) async {
        guard let client = audibleClient else { return }
        isAudibleLoading = true
        defer { isAudibleLoading = false }
        do {
            audibleEpisodes = try await client.getEpisodes(parentAsin: parentAsin)
            audibleError = nil
        } catch {
            audibleError = "Failed to load episodes: \(error.localizedDescription)"
        }
    }

    func loadAudibleOnDeck() async {
        guard audibleClient != nil else { return }
        isAudibleLoading = true
        defer { isAudibleLoading = false }
        do {
            try await fetchOnDeck()
        } catch AudibleError.unauthorized {
            if await refreshAudibleToken() {
                do {
                    try await fetchOnDeck()
                    return
                } catch {}
            }
            audibleError = "Session expired. Try disconnecting and signing in again."
        } catch {
            audibleError = "Failed to load on-deck: \(error.localizedDescription)"
        }
    }

    private func fetchOnDeck() async throws {
        guard let client = audibleClient else { return }
        let books = try await client.getLibrary()
        audibleBooks = books

        let asins = books.map(\.asin)
        guard !asins.isEmpty else {
            audibleOnDeck = []
            return
        }
        let positions = try await client.getListeningPositions(asins: asins)

        let positionMap = Dictionary(uniqueKeysWithValues: positions.map { ($0.asin, $0.positionMs) })
        audibleOnDeck = books.compactMap { book in
            guard let posMs = positionMap[book.asin], posMs > 0 else { return nil }
            return (book: book, positionMs: posMs)
        }.sorted { a, b in
            (a.book.purchaseDate ?? .distantPast) > (b.book.purchaseDate ?? .distantPast)
        }
        audibleError = nil
    }

    func searchAudibleBooks(query: String) -> [AudibleBook] {
        let lowered = query.lowercased()
        return audibleBooks.filter {
            $0.title.lowercased().contains(lowered) ||
            $0.author.lowercased().contains(lowered)
        }
    }

    // MARK: - Audible Playback

    func playAudibleBook(book: AudibleBook, seekOffsetMs: Int = 0) async {
        guard let params = sonosAudibleParams, let controller = activeController else {
            audibleError = "Sonos Audible params not yet discovered. Play an Audible book from the Sonos app first."
            return
        }
        do {
            let uri = params.buildPlayURI(asin: book.asin)
            let didl = params.buildPlayDIDL(asin: book.asin, title: book.title, coverURL: book.coverURL)

            try await controller.playURI(uri, metadata: didl)

            if seekOffsetMs > 0 {
                guard try await waitForPlaying(on: controller) else {
                    audibleError = "Playback didn't start in time to resume at the saved position."
                    return
                }
                let totalSeconds = seekOffsetMs / 1000
                let h = totalSeconds / 3600
                let m = (totalSeconds % 3600) / 60
                let s = totalSeconds % 60
                let target = String(format: "%d:%02d:%02d", h, m, s)
                try await controller.seek(to: target)

                // Verify position was accepted
                #if DEBUG
                if let pos = try? await controller.getPositionInfo() {
                    print("[Audible] Seek target: \(target), current: \(pos.elapsed)")
                }
                #endif
            }

            await refreshPlayback()
        } catch {
            audibleError = "Playback failed: \(error.localizedDescription)"
        }
    }

    func playAudibleChapter(book: AudibleBook, chapter: AudibleChapter) async {
        await playAudibleBook(book: book, seekOffsetMs: chapter.startOffsetMs)
    }

    // MARK: - Apple Music Integration

    var appleMusicCredentials: AppleMusicCredentials?
    var musicDiscovery: MusicDiscoveryProviding = MusicKitDiscoveryProvider()
    var appleMusicAuthStatus: MusicAuthStatus = .notDetermined
    var appleMusicError: String?

    // Legacy UserDefaults keys from the V1 storage scheme. Read once on startup to migrate
    // any pre-existing credentials into the Keychain, then deleted.
    private static let legacyAppleMusicSnKey = "appleMusicSn"
    private static let legacyAppleMusicTokenKey = "appleMusicAccountToken"

    private static func loadCachedAppleMusicCredentials() -> AppleMusicCredentials? {
        if let creds = AppleMusicKeychain.getCredentials() { return creds }

        // Migrate V1 UserDefaults storage into Keychain if present.
        let d = UserDefaults.standard
        guard let token = d.string(forKey: legacyAppleMusicTokenKey), !token.isEmpty else { return nil }
        let sn = d.integer(forKey: legacyAppleMusicSnKey)
        let creds = AppleMusicCredentials(sn: sn, accountToken: token)
        AppleMusicKeychain.setCredentials(creds)
        d.removeObject(forKey: legacyAppleMusicSnKey)
        d.removeObject(forKey: legacyAppleMusicTokenKey)
        return creds
    }

    private func saveAppleMusicCredentials(_ creds: AppleMusicCredentials) {
        AppleMusicKeychain.setCredentials(creds)
    }

    private func clearAppleMusicCredentials() {
        AppleMusicKeychain.deleteCredentials()
        appleMusicCredentials = nil
    }

    /// Loads cached Apple Music credentials or extracts them from the speaker's favorites.
    func discoverAppleMusicCredentials() async {
        if let cached = Self.loadCachedAppleMusicCredentials() {
            appleMusicCredentials = cached
        }
        guard let client = activeClient else { return }
        do {
            let favorites = try await client.callAction(
                service: .contentDirectory,
                action: "Browse",
                params: [
                    ("ObjectID", "FV:2"),
                    ("BrowseFlag", "BrowseDirectChildren"),
                    ("Filter", "*"),
                    ("StartingIndex", "0"),
                    ("RequestedCount", "100"),
                    ("SortCriteria", "")
                ]
            )
            if let didl = favorites["Result"],
               let creds = AppleMusicCredentialsExtractor.extract(favoritesDIDL: didl) {
                appleMusicCredentials = creds
                saveAppleMusicCredentials(creds)
            }
        } catch {
            #if DEBUG
            print("[AppState] Apple Music credentials discovery failed: \(error)")
            #endif
        }
    }

    func appendAppleMusicTrack(_ track: AppleMusicTrack) async {
        await appendAppleMusic(.track(track))
    }

    func appendAppleMusicAlbum(_ album: AppleMusicAlbum) async {
        await appendAppleMusic(.album(album))
    }

    func appendAppleMusicPlaylist(_ playlist: AppleMusicPlaylist) async {
        // Mirrored playlists carry a catalog id (pl.…) that Sonos plays as a single server-side
        // container. Un-mirrored library playlists (isLibrary) have no Sonos-usable container id —
        // the library API's p.xxx id resolves to the wrong content on Sonos — so expand them into
        // individual catalog tracks, each of which has a valid catalog song id.
        if playlist.isLibrary {
            await appendAppleMusicLibraryPlaylist(playlist)
        } else {
            await appendAppleMusic(.playlist(playlist))
        }
    }

    /// Enqueues an un-mirrored library playlist by adding its catalog-resolvable tracks one by one.
    private func appendAppleMusicLibraryPlaylist(_ playlist: AppleMusicPlaylist) async {
        guard let creds = appleMusicCredentials,
              let controller = activeController,
              let device = deviceManager.activeDevice,
              let group = deviceManager.group(for: device.uuid) else { return }
        let tracks: [AppleMusicTrack]
        do {
            tracks = try await musicDiscovery.playlistTracks(playlistId: playlist.id)
        } catch {
            appleMusicError = "Couldn't load this playlist's tracks. Try again."
            return
        }
        let playable = tracks.filter { Int($0.id) != nil }   // catalog-resolvable tracks only
        guard !playable.isEmpty else {
            appleMusicError = "None of this playlist's tracks are available to stream on Sonos."
            return
        }
        appleMusicError = nil
        var firstTrackNumber = 0
        do {
            for (index, track) in playable.enumerated() {
                let pos = try await controller.addToQueue(
                    uri: AppleMusicURIs.trackURI(id: track.id, sn: creds.sn),
                    metadata: AppleMusicURIs.didl(for: .track(track), credentials: creds)
                )
                if index == 0 { firstTrackNumber = pos }
            }
        } catch {
            clearAppleMusicCredentials()
            appleMusicError = "Couldn't add to queue. Favorite an Apple Music item in the Sonos app to refresh credentials."
            return
        }
        await startQueuePlaybackIfIdle(firstTrackNumber: firstTrackNumber,
                                       coordinatorUUID: group.coordinatorUUID, controller: controller)
    }

    private func appendAppleMusic(_ item: AppleMusicPlayable) async {
        guard let creds = appleMusicCredentials,
              let controller = activeController,
              let device = deviceManager.activeDevice,
              let group = deviceManager.group(for: device.uuid) else { return }
        let uri: String
        switch item {
        case .track(let t): uri = AppleMusicURIs.trackURI(id: t.id, sn: creds.sn)
        case .album(let a): uri = AppleMusicURIs.albumContainerURI(id: a.id)
        case .playlist(let p): uri = AppleMusicURIs.playlistContainerURI(id: p.id, isLibrary: p.isLibrary)
        }
        let didl = AppleMusicURIs.didl(for: item, credentials: creds)

        appleMusicError = nil

        // Add to queue. If this throws, credentials are likely stale.
        let firstTrackNumber: Int
        do {
            firstTrackNumber = try await controller.addToQueue(uri: uri, metadata: didl)
        } catch {
            clearAppleMusicCredentials()
            appleMusicError = "Couldn't add to queue. Favorite an Apple Music item in the Sonos app to refresh credentials."
            #if DEBUG
            print("[AppState] Apple Music addToQueue failed: \(error)")
            #endif
            return
        }
        await startQueuePlaybackIfIdle(firstTrackNumber: firstTrackNumber,
                                       coordinatorUUID: group.coordinatorUUID, controller: controller)
    }

    /// If the speaker isn't already playing from its queue, point the transport at the queue,
    /// seek to the newly enqueued track, and start playback. No-op when the speaker is already
    /// playing from the queue (the user is intentionally building a queue).
    private func startQueuePlaybackIfIdle(firstTrackNumber: Int, coordinatorUUID: String, controller: PlaybackController) async {
        guard firstTrackNumber > 0 else { return }
        let state = (try? await controller.getTransportState()) ?? .stopped
        let mediaInfo = try? await controller.getMediaInfo()
        let isOnQueue = mediaInfo?.uri.hasPrefix("x-rincon-queue:") ?? false
        if state == .playing && isOnQueue { return }  // Don't interrupt active playback.
        do {
            if !isOnQueue {
                try await controller.playURI("x-rincon-queue:\(coordinatorUUID)#0", metadata: "")
            }
            try await controller.seekToTrack(firstTrackNumber)
            if state != .playing { try await controller.play() }
            await refreshPlayback()
        } catch {
            appleMusicError = "Added to queue, but playback didn't start. Try again."
            #if DEBUG
            print("[AppState] Apple Music auto-play failed (queue already appended): \(error)")
            #endif
        }
    }
}
