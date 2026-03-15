// SonoBar/Views/PlexTrackListView.swift
import SwiftUI
import SonoBarKit

struct PlexTrackListView: View {
    @Environment(AppState.self) private var appState
    let album: PlexAlbum
    let tracks: [PlexTrack]
    let isLoading: Bool

    /// Index of the first track with a non-zero viewOffset (for resume).
    private var resumeTrackIndex: Int? {
        tracks.firstIndex(where: { $0.viewOffset > 0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && tracks.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading tracks...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No tracks found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Album header
                        VStack(spacing: 4) {
                            Text(album.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(album.artist ?? "")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                        // Play All / Resume buttons
                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    await appState.playPlexAlbum(albumId: album.id)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                    Text("Play All")
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)

                            if let resumeIdx = resumeTrackIndex {
                                let track = tracks[resumeIdx]
                                Button {
                                    Task {
                                        await appState.playPlexAlbum(
                                            albumId: album.id,
                                            startTrackIndex: resumeIdx,
                                            seekOffset: track.viewOffset / 1000
                                        )
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 10))
                                        Text("Resume")
                                            .font(.system(size: 11))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 8)

                        // Track list
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    Task {
                                        await appState.playPlexAlbum(
                                            albumId: album.id,
                                            startTrackIndex: index
                                        )
                                    }
                                } label: {
                                    trackRow(track: track)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Track Row

    private func trackRow(track: PlexTrack) -> some View {
        HStack(spacing: 8) {
            // Track number
            Text("\(track.index)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Title and progress
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                if track.viewOffset > 0 && track.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.accentColor)
                                .frame(
                                    width: geo.size.width * CGFloat(track.viewOffset) / CGFloat(track.duration),
                                    height: 3
                                )
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            // Duration
            Text(formatDuration(track.duration))
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Formats milliseconds into a human-readable duration like "3:45" or "1:02:30".
    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
