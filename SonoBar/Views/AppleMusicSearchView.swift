import SwiftUI
import SonoBarKit

private enum AMMode: String, CaseIterable, Identifiable {
    case search = "Search", playlists = "Playlists", library = "Library"
    var id: String { rawValue }
}

struct AppleMusicSearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query: String = ""
    @State private var results: AppleMusicSearchResults?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var activeTask: Task<Void, Never>?
    @State private var selectedAlbum: AppleMusicAlbum?
    @State private var selectedArtist: AppleMusicArtist?
    @State private var selectedPlaylist: AppleMusicPlaylist?

    @State private var mode: AMMode = .search

    @State private var libraryPlaylists: [AppleMusicPlaylist] = []
    @State private var libraryAlbums: [AppleMusicAlbum] = []
    @State private var librarySongs: [AppleMusicTrack] = []
    @State private var libraryError: String?
    @State private var libraryDidLoad = false
    @State private var libraryTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if let error = appState.appleMusicError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            if appState.appleMusicCredentials == nil {
                emptyState
            } else if appState.appleMusicAuthStatus == .denied {
                authDeniedState
            } else {
                content
                    .sheet(item: $selectedAlbum) { a in AppleMusicAlbumDetailView(album: a) }
                    .sheet(item: $selectedArtist) { a in AppleMusicArtistDetailView(artist: a) }
                    .sheet(item: $selectedPlaylist) { p in AppleMusicPlaylistDetailView(playlist: p) }
            }
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

    private var authDeniedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 32)).foregroundColor(.secondary)
            Text("Allow Apple Music access in System Settings to browse your library.")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(AMMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.bottom, 6)

            switch mode {
            case .search:
                searchBar
                resultsBody
            case .playlists:
                playlistsBody
            case .library:
                libraryBody
            }
        }
        .task(id: mode) {
            if mode != .search && !libraryDidLoad { reloadLibrary() }
        }
        .onDisappear { libraryTask?.cancel() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            // Swap the magnifier for a spinner while a search is in flight, so users
            // get feedback on every query — not just the first one.
            if isSearching {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
            } else {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
            }
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

    @ViewBuilder
    private var playlistsBody: some View {
        if let error = libraryError {
            libraryErrorView(error)
        } else if !libraryDidLoad {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if libraryPlaylists.isEmpty {
            Text("No playlists in your library.")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    playlistsSection(libraryPlaylists)
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var libraryBody: some View {
        if let error = libraryError {
            libraryErrorView(error)
        } else if !libraryDidLoad {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if libraryAlbums.isEmpty && librarySongs.isEmpty {
            Text("No albums or songs in your library.")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !libraryAlbums.isEmpty { albumsSection(libraryAlbums) }
                    if !librarySongs.isEmpty  { librarySongsSection(librarySongs) }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    private func libraryErrorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Text(error).font(.system(size: 11)).foregroundColor(.secondary)
            Button("Retry") {
                libraryError = nil
                libraryDidLoad = false
                reloadLibrary()
            }.buttonStyle(.plain).font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tracksSection(_ tracks: [AppleMusicTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tracks").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            // Plain VStack inside the outer LazyVStack — nesting LazyVStacks defeats
            // the outer's laziness by forcing eager child expansion.
            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    Button { Task { await appState.appendAppleMusicTrack(track) } } label: {
                        rowContent(artwork: track.artworkURL, title: track.title, subtitle: track.artist)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func albumsSection(_ albums: [AppleMusicAlbum], title: String = "Albums") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            VStack(spacing: 0) {
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
            VStack(spacing: 0) {
                ForEach(artists) { artist in
                    Button { selectedArtist = artist } label: {
                        rowContent(artwork: nil, title: artist.name, subtitle: nil)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func playlistsSection(_ playlists: [AppleMusicPlaylist]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Playlists").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            VStack(spacing: 0) {
                ForEach(playlists) { playlist in
                    Button { selectedPlaylist = playlist } label: {
                        rowContent(artwork: playlist.artworkURL, title: playlist.name, subtitle: nil)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func librarySongsSection(_ songs: [AppleMusicTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Songs").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            VStack(spacing: 0) {
                ForEach(songs) { song in
                    Button { Task { await appState.appendAppleMusicTrack(song) } } label: {
                        rowContent(artwork: song.artworkURL, title: song.title, subtitle: song.artist)
                    }
                    .buttonStyle(.plain)
                    .disabled(Int(song.id) == nil)
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
        guard !newQuery.isEmpty else {
            results = nil
            return
        }
        activeTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let r = try await appState.musicDiscovery.search(newQuery)
                guard !Task.isCancelled else { return }
                results = r
            } catch {
                guard !Task.isCancelled else { return }
                results = nil
                errorMessage = "Search failed. Try again."
            }
        }
    }

    private func loadLibrary() async {
        do {
            async let p = appState.musicDiscovery.libraryPlaylists()
            async let a = appState.musicDiscovery.libraryAlbums()
            async let s = appState.musicDiscovery.librarySongs()
            let (pl, al, so) = try await (p, a, s)
            guard !Task.isCancelled else { return }
            libraryPlaylists = pl
            libraryAlbums = al
            librarySongs = so
            libraryError = nil
        } catch {
            guard !Task.isCancelled else { return }   // ignore cancellation (provider wraps it as networkError)
            libraryError = "Couldn't load your library. Retry."
        }
        libraryDidLoad = true
    }

    private func reloadLibrary() {
        libraryTask?.cancel()
        libraryTask = Task { await loadLibrary() }
    }
}
