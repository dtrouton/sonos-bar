import SwiftUI
import SonoBarKit

struct AppleMusicPlaylistDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let playlist: AppleMusicPlaylist

    @State private var tracks: [AppleMusicTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) { header; Divider(); bodyContent }
            .frame(width: 360, height: 480)
            .task { await load() }
    }

    private var header: some View {
        HStack {
            Button("Close") { dismiss() }.buttonStyle(.plain).font(.system(size: 11))
            Spacer()
            Text(playlist.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
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
                    cover
                    Button { Task { await appState.appendAppleMusicPlaylist(playlist) } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.badge.plus").font(.system(size: 10))
                            Text("Add all to queue").font(.system(size: 11))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15)).cornerRadius(14)
                    }
                    .buttonStyle(.plain).padding(.vertical, 8)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, t in
                            let playable = Int(t.id) != nil
                            Button { Task { await appState.appendAppleMusicTrack(t) } } label: {
                                trackRow(index: index + 1, track: t, playable: playable)
                            }
                            .buttonStyle(.plain).disabled(!playable)
                        }
                    }
                }
            }
        }
    }

    private var cover: some View {
        artworkThumbnail(playlist.artworkURL, size: 120)
            .cornerRadius(6)
            .padding(.top, 12)
    }

    private func trackRow(index: Int, track: AppleMusicTrack, playable: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(index)").font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary).frame(width: 20, alignment: .trailing)
            artworkThumbnail(track.artworkURL, size: 32).cornerRadius(3)
            Text(track.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .foregroundColor(playable ? .primary : .secondary)
            if !playable {
                Text("Not on Sonos").font(.system(size: 9)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4).contentShape(Rectangle())
    }

    @ViewBuilder
    private func artworkThumbnail(_ url: URL?, size: CGFloat) -> some View {
        if let url {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                placeholder: { Color.secondary.opacity(0.15) }
                .frame(width: size, height: size).clipped()
        } else {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "music.note.list").font(.system(size: size * 0.3)).foregroundColor(.secondary)
            }
            .frame(width: size, height: size)
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tracks = try await appState.musicDiscovery.playlistTracks(playlistId: playlist.id)
        } catch {
            errorMessage = "Couldn't load playlist. Try again."
        }
    }
}
