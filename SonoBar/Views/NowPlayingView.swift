// SonoBar/Views/NowPlayingView.swift
import SwiftUI

struct NowPlayingView: View {
    var navigateToRooms: () -> Void = {}
    var onSeek: ((Double) -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    @State private var roomName = "No Speaker"
    @State private var groupInfo: String? = nil
    @State private var trackTitle = "Not Playing"
    @State private var trackArtist = ""
    @State private var trackAlbum = ""
    @State private var sourceBadge = ""
    @State private var elapsed = "0:00"
    @State private var duration = "0:00"
    @State private var progress: Double = 0
    @State private var isPlaying = false
    @State private var volume: Double = 50
    @State private var isMuted = false

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
                Slider(value: $progress, in: 0...1) { editing in
                    if !editing { onSeek?(progress) }
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
                Button(action: { onPrevious?() }) {
                    Image(systemName: "backward.fill").font(.system(size: 16))
                }
                Button(action: { onPlayPause?() }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                Button(action: { onNext?() }) {
                    Image(systemName: "forward.fill").font(.system(size: 16))
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            // Volume
            VolumeSliderView(
                volume: $volume,
                isMuted: $isMuted,
                onVolumeChange: { _ in /* set volume */ },
                onMuteToggle: { isMuted.toggle() }
            )
            .padding(.bottom, 8)
        }
    }
}
