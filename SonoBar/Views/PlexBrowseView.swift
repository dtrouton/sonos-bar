// SonoBar/Views/PlexBrowseView.swift
import SwiftUI
import SonoBarKit

struct PlexBrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    /// Simple navigation stack: each entry describes a pushed view.
    enum PlexNav: Equatable {
        case albumList(library: PlexLibrary)
        case trackList(album: PlexAlbum)
    }

    @State private var navigationPath: [PlexNav] = []

    /// The current library section ID when browsing inside a library, for scoped search.
    private var currentSectionId: String? {
        for nav in navigationPath {
            if case .albumList(let library) = nav { return library.id }
        }
        return nil
    }

    var body: some View {
        if appState.plexClient == nil {
            PlexSetupView()
        } else {
            VStack(spacing: 0) {
                // Search bar — always visible
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onChange(of: searchText) { _, newValue in
                            searchTask?.cancel()
                            if newValue.isEmpty {
                                appState.plexAlbums = []
                                return
                            }
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                guard !Task.isCancelled else { return }
                                await appState.searchPlex(query: newValue, sectionId: currentSectionId)
                            }
                        }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Back button when navigated deeper
                if !navigationPath.isEmpty && searchText.isEmpty {
                    HStack(spacing: 4) {
                        Button {
                            navigationPath.removeLast()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11))
                                Text("Back")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                if !searchText.isEmpty {
                    // Search results overlay any navigation level
                    PlexAlbumListView(
                        libraryTitle: "Search Results",
                        albums: appState.plexAlbums,
                        isLoading: appState.isPlexLoading
                    ) { album in
                        searchText = ""
                        Task { await appState.loadPlexTracks(albumId: album.id) }
                        navigationPath.append(.trackList(album: album))
                    }
                } else {
                    // Show current level
                    switch navigationPath.last {
                    case .albumList(let library):
                        PlexAlbumListView(
                            libraryTitle: library.title,
                            albums: appState.plexAlbums,
                            isLoading: appState.isPlexLoading
                        ) { album in
                            Task { await appState.loadPlexTracks(albumId: album.id) }
                            navigationPath.append(.trackList(album: album))
                        }
                        .onAppear {
                            Task { await appState.loadPlexAlbums(sectionId: library.id) }
                        }

                    case .trackList(let album):
                        PlexTrackListView(
                            album: album,
                            tracks: appState.plexTracks,
                            isLoading: appState.isPlexLoading
                        )

                    case nil:
                        plexHome
                    }
                }
            }
            .onAppear {
                Task {
                    await appState.loadPlexLibraries()
                    await appState.loadPlexOnDeck()
                }
            }
        }
    }

    private var searchPlaceholder: String {
        if let nav = navigationPath.last, case .albumList(let lib) = nav {
            return "Search \(lib.title)"
        }
        return "Search Plex"
    }

    // MARK: - Plex Home

    private var plexHome: some View {
        VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Continue Listening section
                        if !appState.plexOnDeck.isEmpty {
                            Text("Continue Listening")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)

                            LazyVStack(spacing: 0) {
                                ForEach(appState.plexOnDeck) { track in
                                    Button {
                                        Task { await appState.resumePlexTrack(track) }
                                    } label: {
                                        onDeckRow(track: track)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Libraries section
                        if !appState.plexLibraries.isEmpty {
                            Text("Libraries")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)

                            LazyVStack(spacing: 0) {
                                ForEach(appState.plexLibraries) { library in
                                    Button {
                                        Task { await appState.loadPlexAlbums(sectionId: library.id) }
                                        navigationPath.append(.albumList(library: library))
                                    } label: {
                                        HStack {
                                            Image(systemName: "music.note.house")
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                                .frame(width: 24)
                                            Text(library.title)
                                                .font(.system(size: 12))
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Settings link
                        Divider()
                            .padding(.horizontal, 12)

                        Button {
                            navigationPath = []
                            // Show setup view by disconnecting
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)
                                Text("Plex Settings")
                                    .font(.system(size: 12))
                                Spacer()
                                if let host = appState.plexClient?.host {
                                    Text(host)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Error display
                        if let error = appState.plexError {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 11))
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
            }
        }


    // MARK: - On Deck Row

    private func onDeckRow(track: PlexTrack) -> some View {
        HStack(spacing: 10) {
            // Thumb image
            PlexArtworkView(thumbPath: track.thumbPath)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Title and progress
            VStack(alignment: .leading, spacing: 2) {
                Text(track.albumTitle.isEmpty ? track.title : track.albumTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                let progressPct = track.duration > 0
                    ? Int(Double(track.viewOffset) / Double(track.duration) * 100)
                    : 0
                let remainingMin = max(0, (track.duration - track.viewOffset) / 60_000)
                Text("\(progressPct)% \u{00B7} \(remainingMin)m left")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - PlexArtworkView

/// Loads and displays Plex artwork from a thumb path.
struct PlexArtworkView: View {
    let thumbPath: String?
    @Environment(AppState.self) private var appState
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: thumbPath) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> NSImage? {
        guard let thumbPath, !thumbPath.isEmpty,
              let url = appState.plexClient?.thumbURL(path: thumbPath) else {
            return nil
        }
        return await ArtworkCache.shared.image(for: url.absoluteString)
    }
}
