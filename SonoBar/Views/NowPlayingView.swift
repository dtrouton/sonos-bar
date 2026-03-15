// SonoBar/Views/NowPlayingView.swift
import AppKit
import SwiftUI
import SonoBarKit

struct NowPlayingView: View {
    @Environment(AppState.self) private var appState
    var navigateToRooms: () -> Void = {}

    /// Local volume binding for the slider; synced from appState on appear/change.
    @State private var sliderVolume: Double = 0
    @State private var sliderMuted: Bool = false

    private var roomName: String {
        appState.deviceManager.activeDevice?.roomName ?? "No Speaker"
    }

    private var groupInfo: String? {
        guard let device = appState.deviceManager.activeDevice,
              let group = appState.deviceManager.group(for: device.uuid),
              !group.isStandalone else { return nil }
        let others = group.members
            .filter { $0.uuid != device.uuid }
            .map { $0.zoneName }
        guard !others.isEmpty else { return nil }
        return others.joined(separator: ", ")
    }

    private var isTV: Bool {
        appState.playbackState.currentTrack?.uri.hasPrefix("x-sonos-htastream:") == true
    }

    private var isLineIn: Bool {
        appState.playbackState.currentTrack?.uri.hasPrefix("x-rincon-stream:") == true
    }

    private var trackTitle: String {
        if isTV { return "TV" }
        if isLineIn { return "Line-In" }
        return appState.playbackState.currentTrack?.title ?? "Not Playing"
    }

    private var trackArtist: String {
        appState.playbackState.currentTrack?.artist ?? ""
    }

    private var trackAlbum: String {
        appState.playbackState.currentTrack?.album ?? ""
    }

    private var elapsed: String {
        appState.playbackState.currentTrack?.elapsed ?? "0:00"
    }

    private var duration: String {
        appState.playbackState.currentTrack?.duration ?? "0:00"
    }

    private var progress: Double {
        guard let track = appState.playbackState.currentTrack else { return 0 }
        let elapsedSeconds = parseTime(track.elapsed)
        let durationSeconds = parseTime(track.duration)
        guard durationSeconds > 0 else { return 0 }
        return Double(elapsedSeconds) / Double(durationSeconds)
    }

    private var isPlaying: Bool {
        appState.playbackState.transportState == .playing
    }

    private var sourceBadge: String {
        guard let uri = appState.playbackState.currentTrack?.uri else { return "" }
        if let plexHost = appState.plexClient?.host, uri.contains(plexHost) { return "Plex" }
        if uri.contains("spotify") { return "Spotify" }
        if uri.contains("apple") { return "Apple Music" }
        if uri.contains("tidal") { return "Tidal" }
        if uri.contains("amazon") { return "Amazon Music" }
        if uri.contains("youtube") { return "YouTube Music" }
        if uri.contains("deezer") { return "Deezer" }
        if uri.contains("soundcloud") { return "SoundCloud" }
        if uri.contains("pandora") { return "Pandora" }
        if uri.contains("audible") { return "Audible" }
        if uri.contains("plex") { return "Plex" }
        if uri.contains("bbc") { return "BBC Sounds" }
        if uri.contains("tunein") || uri.contains("radiotime") { return "TuneIn" }
        if uri.contains("sonos-radio") || uri.contains("sonosradio") { return "Sonos Radio" }
        if uri.hasPrefix("x-rincon-mp3radio:") || uri.hasPrefix("aac:") || uri.hasPrefix("hls:") { return "Radio" }
        if uri.hasPrefix("x-file-cifs:") || uri.hasPrefix("x-smb:") { return "Library" }
        if uri.hasPrefix("x-rincon-stream:") { return "Line-In" }
        if uri.hasPrefix("x-sonos-htastream:") { return "TV" }
        if uri.contains("airplay") { return "AirPlay" }
        return ""
    }

    @State private var scrubProgress: Double = 0
    @State private var isScrubbing: Bool = false
    @State private var refreshTimer: Timer?
    @State private var showQueue: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Room selector
            Button(action: navigateToRooms) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(roomName)
                            .font(.system(size: 13, weight: .semibold))
                        if let groupInfo {
                            Text(groupInfo)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)

            if showQueue {
                // Queue list
                QueueListView(
                    items: appState.contentItems,
                    currentTrackURI: appState.playbackState.currentTrack?.uri,
                    onTap: { item in
                        guard let idx = appState.contentItems.firstIndex(where: { $0.id == item.id }) else { return }
                        Task {
                            try? await appState.activeController?.seekToTrack(idx + 1)
                            await appState.refreshPlayback()
                        }
                    }
                )
            } else {
                // Album art
                Group {
                    if let albumArt = appState.albumArtImage {
                        Image(nsImage: albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: 160, height: 160)
                .padding(.bottom, 8)

                // Track info
                VStack(spacing: 2) {
                    Text(trackTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(trackArtist.isEmpty ? "" : "\(trackArtist) \u{2014} \(trackAlbum)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if !sourceBadge.isEmpty {
                        Text(sourceBadge)
                            .font(.system(size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(10)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Progress (scrubbable) — hidden for TV/line-in which have no position data
            if !isTV && !isLineIn {
            VStack(spacing: 4) {
                Slider(value: $scrubProgress, in: 0...1) { editing in
                    isScrubbing = editing
                    if !editing {
                        let totalSeconds = parseTime(duration)
                        let targetSeconds = Int(Double(totalSeconds) * scrubProgress)
                        let h = targetSeconds / 3600
                        let m = (targetSeconds % 3600) / 60
                        let s = targetSeconds % 60
                        let target = String(format: "%d:%02d:%02d", h, m, s)
                        Task {
                            try? await appState.activeController?.seek(to: target)
                            await appState.refreshPlayback()
                        }
                    }
                }
                    .controlSize(.mini)
                HStack {
                    Text(elapsed).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Text(duration).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            } // end if !isTV && !isLineIn

            // Transport controls
            HStack(spacing: 28) {
                Button {
                    showQueue.toggle()
                    if showQueue { Task { await appState.browseQueue() } }
                } label: {
                    Image(systemName: showQueue ? "list.bullet.circle.fill" : "list.bullet")
                        .font(.system(size: 14))
                        .foregroundColor(showQueue ? .accentColor : .primary)
                }
                Button(action: { performPrevious() }) {
                    Image(systemName: "backward.fill").font(.system(size: 16))
                }
                Button(action: { performPlayPause() }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                Button(action: { performNext() }) {
                    Image(systemName: "forward.fill").font(.system(size: 16))
                }
                Menu {
                    ForEach([15, 30, 45, 60], id: \.self) { mins in
                        Button("\(mins) minutes") {
                            Task { await appState.setSleepTimer(minutes: mins) }
                        }
                    }
                    if appState.sleepTimerEndDate != nil {
                        Divider()
                        Button("Cancel Timer", role: .destructive) {
                            Task { await appState.cancelSleepTimer() }
                        }
                    }
                } label: {
                    Image(systemName: appState.sleepTimerEndDate != nil ? "moon.fill" : "moon")
                        .font(.system(size: 14))
                        .foregroundColor(appState.sleepTimerEndDate != nil ? .accentColor : .primary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            // Sleep timer countdown
            if let endDate = appState.sleepTimerEndDate, endDate > .now {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(endDate.timeIntervalSince(context.date)))
                    if remaining > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(formatCountdown(remaining))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundColor(.secondary)
                            Button {
                                Task { await appState.cancelSleepTimer() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }

            Spacer(minLength: 0)

            // Volume
            VolumeSliderView(
                volume: $sliderVolume,
                isMuted: $sliderMuted,
                onVolumeChange: { level in
                    Task {
                        try? await appState.activeController?.setVolume(level)
                        await appState.refreshPlayback()
                    }
                },
                onMuteToggle: {
                    sliderMuted.toggle()
                    Task {
                        try? await appState.activeController?.setMute(sliderMuted)
                        await appState.refreshPlayback()
                    }
                }
            )
            .padding(.bottom, 8)
        }
        .onAppear {
            sliderVolume = Double(appState.playbackState.volume)
            sliderMuted = appState.playbackState.isMuted
            scrubProgress = progress
            Task { await appState.refreshSleepTimer() }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task {
                    await appState.refreshPlayback()
                    await appState.reportPlexProgressIfNeeded()
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onChange(of: appState.playbackState.volume) { _, newValue in
            sliderVolume = Double(newValue)
        }
        .onChange(of: appState.playbackState.isMuted) { _, newValue in
            sliderMuted = newValue
        }
        .onChange(of: progress) { _, newValue in
            if !isScrubbing {
                scrubProgress = newValue
            }
        }
    }

    // MARK: - Actions

    private func performPlayPause() {
        Task {
            if isPlaying {
                try? await appState.activeController?.pause()
            } else {
                try? await appState.activeController?.play()
            }
            await appState.refreshPlayback()
        }
    }

    private func performNext() {
        Task {
            try? await appState.activeController?.next()
            await appState.refreshPlayback()
        }
    }

    private func performPrevious() {
        Task {
            try? await appState.activeController?.previous()
            await appState.refreshPlayback()
        }
    }

    // MARK: - Helpers

    /// Formats seconds into "Xh Ym" or "X:SS" countdown string.
    private func formatCountdown(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else if m > 0 {
            return "\(m):\(String(format: "%02d", s))"
        } else {
            return "0:\(String(format: "%02d", s))"
        }
    }

    /// Parses a time string like "0:03:45" or "3:45" into total seconds.
    private func parseTime(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }
}
