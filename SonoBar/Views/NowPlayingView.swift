// SonoBar/Views/NowPlayingView.swift
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

    private var trackTitle: String {
        appState.playbackState.currentTrack?.title ?? "Not Playing"
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
        if uri.contains("spotify") { return "Spotify" }
        if uri.contains("apple") { return "Apple Music" }
        if uri.contains("plex") { return "Plex" }
        if uri.contains("bbc") { return "BBC Sounds" }
        if uri.hasPrefix("x-rincon-mp3radio:") || uri.hasPrefix("aac:") { return "Radio" }
        if uri.hasPrefix("x-file-cifs:") || uri.hasPrefix("x-smb:") { return "Library" }
        return ""
    }

    @State private var scrubProgress: Double = 0

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

            // Album art placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 200, height: 200)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                )
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

            // Progress (scrubbable)
            VStack(spacing: 4) {
                Slider(value: $scrubProgress, in: 0...1) { editing in
                    if !editing {
                        // Seek not yet wired — will be connected to PlaybackController.seek()
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

            // Transport controls
            HStack(spacing: 28) {
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
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

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
        }
        .onChange(of: appState.playbackState.volume) { _, newValue in
            sliderVolume = Double(newValue)
        }
        .onChange(of: appState.playbackState.isMuted) { _, newValue in
            sliderMuted = newValue
        }
        .onChange(of: progress) { _, newValue in
            scrubProgress = newValue
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
