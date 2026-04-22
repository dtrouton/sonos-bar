import SwiftUI
import SonoBarKit

struct AppleMusicAlbumDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let album: AppleMusicAlbum

    @State private var tracks: [AppleMusicTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bodyContent
        }
        .frame(width: 360, height: 480)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Button("Close") { dismiss() }.buttonStyle(.plain).font(.system(size: 11))
            Spacer()
            VStack(spacing: 1) {
                Text(album.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let a = album.artist {
                    Text(a).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Color.clear.frame(width: 40)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let error = errorMessage, tracks.isEmpty {
            VStack(spacing: 8) {
                Text(error).font(.system(size: 11)).foregroundColor(.secondary)
                Button("Retry") { Task { await load() } }.buttonStyle(.plain).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading && tracks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        Task { await appState.appendAppleMusicAlbum(album) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.badge.plus").font(.system(size: 10))
                            Text("Add all to queue").font(.system(size: 11))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, t in
                            Button {
                                Task { await appState.appendAppleMusicTrack(t) }
                            } label: {
                                trackRow(index: index + 1, track: t)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func trackRow(index: Int, track: AppleMusicTrack) -> some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(track.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer()
            if let d = track.durationSec {
                Text(formatDuration(d))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private func load() async {
        guard let client = appState.itunesSearchClient, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tracks = try await client.albumTracks(albumId: album.id)
        } catch {
            errorMessage = "Couldn't load album. Try again."
        }
    }
}
