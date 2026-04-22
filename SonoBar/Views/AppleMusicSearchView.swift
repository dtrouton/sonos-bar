import SwiftUI
import SonoBarKit

struct AppleMusicSearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query: String = ""
    @State private var results: AppleMusicSearchResults?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var activeTask: Task<Void, Never>?
    @State private var selectedAlbum: AppleMusicAlbum?
    @State private var selectedArtist: AppleMusicArtist?

    var body: some View {
        if appState.appleMusicCredentials == nil {
            emptyState
        } else {
            content
                .sheet(item: $selectedAlbum) { a in AppleMusicAlbumDetailView(album: a) }
                .sheet(item: $selectedArtist) { a in AppleMusicArtistDetailView(artist: a) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note").font(.system(size: 32)).foregroundColor(.secondary)
            Text("Favorite one Apple Music track in the Sonos app to enable playback here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) { searchBar; resultsBody }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
            TextField("Search Apple Music", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if query.isEmpty {
            Text("Type to search the Apple Music catalog.")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            VStack(spacing: 8) {
                Text(error).font(.system(size: 11)).foregroundColor(.secondary)
                Button("Retry") { scheduleSearch(query) }.buttonStyle(.plain).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSearching && results == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = results {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !r.tracks.isEmpty  { tracksSection(r.tracks) }
                    if !r.albums.isEmpty  { albumsSection(r.albums) }
                    if !r.artists.isEmpty { artistsSection(r.artists) }
                    if r.tracks.isEmpty && r.albums.isEmpty && r.artists.isEmpty {
                        Text("No results.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    private func tracksSection(_ tracks: [AppleMusicTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tracks").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(tracks) { track in
                    Button { Task { await appState.appendAppleMusicTrack(track) } } label: {
                        rowContent(artwork: track.artworkURL, title: track.title, subtitle: track.artist)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func albumsSection(_ albums: [AppleMusicAlbum]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Albums").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    Button { selectedAlbum = album } label: {
                        rowContent(artwork: album.artworkURL, title: album.title, subtitle: album.artist)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func artistsSection(_ artists: [AppleMusicArtist]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Artists").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(artists) { artist in
                    Button { selectedArtist = artist } label: {
                        rowContent(artwork: nil, title: artist.name, subtitle: nil)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func rowContent(artwork: URL?, title: String, subtitle: String?) -> some View {
        HStack(spacing: 8) {
            artworkThumb(artwork)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                if let s = subtitle {
                    Text(s).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func artworkThumb(_ url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                placeholder: { Color.secondary.opacity(0.15) }
                .frame(width: 32, height: 32).cornerRadius(3)
        } else {
            Color.secondary.opacity(0.15).frame(width: 32, height: 32).cornerRadius(3)
        }
    }

    private func scheduleSearch(_ newQuery: String) {
        activeTask?.cancel()
        errorMessage = nil
        guard !newQuery.isEmpty, let client = appState.itunesSearchClient else {
            results = nil
            return
        }
        activeTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let r = try await client.search(newQuery)
                guard !Task.isCancelled else { return }
                results = r
            } catch {
                guard !Task.isCancelled else { return }
                results = nil
                errorMessage = "Search failed. Try again."
            }
        }
    }
}
