// SonoBar/Views/PlexBrowseView.swift
import SwiftUI
import SonoBarKit

struct PlexBrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var showsSettings = false
    @State private var connectionAttempt = 0
    @State private var response: BrowseResponse?

    /// Simple navigation stack: each entry describes a pushed view.
    enum PlexNav: Equatable {
        case albumList(library: PlexLibrary)
        case trackList(album: PlexAlbum)
    }

    @State private var navigationPath: [PlexNav] = []

    private enum BrowseRequest: Equatable {
        case albums(String)
        case tracks(String)
        case search(String, sectionId: String?)
    }

    private struct BrowseResponse {
        let request: BrowseRequest
        var albums: [PlexAlbum] = []
        var tracks: [PlexTrack] = []
        var error: String?
    }

    private var browseRequest: BrowseRequest? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { return .search(query, sectionId: currentSectionId) }
        switch navigationPath.last {
        case .albumList(let library): return .albums(library.id)
        case .trackList(let album): return .tracks(album.id)
        case nil: return nil
        }
    }

    private var currentResponse: BrowseResponse? {
        response?.request == browseRequest ? response : nil
    }

    private struct ConnectionRequest: Equatable {
        let client: ObjectIdentifier?
        let attempt: Int
    }

    private var clientID: ObjectIdentifier? {
        appState.plexClient.map(ObjectIdentifier.init)
    }

    /// The current library section ID when browsing inside a library, for scoped search.
    private var currentSectionId: String? {
        for nav in navigationPath {
            if case .albumList(let library) = nav { return library.id }
        }
        return nil
    }

    var body: some View {
        plexContent
            .task(id: ConnectionRequest(client: clientID, attempt: connectionAttempt)) {
                guard appState.plexConnection != .signInRequired else { return }
                await appState.loadPlexHome()
            }
            .onChange(of: clientID) {
                showsSettings = false
                searchText = ""
                navigationPath = []
                response = nil
            }
    }

    @ViewBuilder
    private var plexContent: some View {
        if appState.plexClient == nil || appState.plexConnection == .signInRequired {
            PlexSetupView()
        } else if showsSettings {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showsSettings = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .padding(12)

                PlexSetupView()
            }
        } else if appState.plexConnection == .checking {
            ProgressView("Checking Plex connection…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let message) = appState.plexConnection {
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Retry") { connectionAttempt += 1 }
                    Button("Plex Settings") { showsSettings = true }
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // Search bar — always visible
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
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

                if let error = appState.plexError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                if !navigationPath.isEmpty && !isSearching {
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

                if let error = currentResponse?.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isSearching {
                    // Search results overlay any navigation level
                    PlexAlbumListView(
                        libraryTitle: "Search Results",
                        albums: currentResponse?.albums ?? [],
                        isLoading: currentResponse == nil
                    ) { album in
                        searchText = ""
                        navigationPath.append(.trackList(album: album))
                    }
                } else {
                    // Show current level
                    switch navigationPath.last {
                    case .albumList(let library):
                        PlexAlbumListView(
                            libraryTitle: library.title,
                            albums: currentResponse?.albums ?? [],
                            isLoading: currentResponse == nil
                        ) { album in
                            navigationPath.append(.trackList(album: album))
                        }

                    case .trackList(let album):
                        PlexTrackListView(
                            album: album,
                            tracks: currentResponse?.tracks ?? [],
                            isLoading: currentResponse == nil
                        )

                    case nil:
                        plexHome
                    }
                }
            }
            .task(id: browseRequest) {
                await loadBrowseResponse(for: browseRequest)
            }
        }
    }

    private var isSearching: Bool {
        if case .search = browseRequest { return true }
        return false
    }

    private func loadBrowseResponse(for request: BrowseRequest?) async {
        guard let request, let client = appState.plexClient, !Task.isCancelled else { return }
        response = nil
        var result = BrowseResponse(request: request)
        do {
            switch request {
            case .albums(let sectionId):
                result.albums = try await client.getAlbums(sectionId: sectionId)
            case .tracks(let albumId):
                result.tracks = try await client.getTracks(albumId: albumId)
            case .search(let query, let sectionId):
                try await Task.sleep(for: .milliseconds(300))
                result.albums = try await client.search(query: query, sectionId: sectionId)
            }
        } catch {
            guard !Task.isCancelled, appState.plexClient === client, browseRequest == request else { return }
            if error as? PlexError == .unauthorized {
                appState.requirePlexSignIn(for: client)
                return
            }
            result.error = error.localizedDescription
        }
        guard !Task.isCancelled, appState.plexClient === client, browseRequest == request else { return }
        response = result
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
                        } else {
                            Text("No music or audiobook libraries are available to this Plex account.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                        }

                        if let error = appState.plexOnDeckError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                        }

                        // Settings link
                        Divider()
                            .padding(.horizontal, 12)

                        Button {
                            showsSettings = true
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
