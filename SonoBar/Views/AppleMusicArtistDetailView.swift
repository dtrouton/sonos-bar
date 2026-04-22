import SwiftUI
import SonoBarKit

struct AppleMusicArtistDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let artist: AppleMusicArtist

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
            Text("Top tracks — \(artist.name)")
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
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

    private func trackRow(index: Int, track: AppleMusicTrack) -> some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                if let album = track.album {
                    Text(album).font(.system(size: 10))
                        .foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let client = appState.itunesSearchClient, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tracks = try await client.artistTopTracks(artistId: artist.id)
        } catch {
            errorMessage = "Couldn't load artist. Try again."
        }
    }
}
