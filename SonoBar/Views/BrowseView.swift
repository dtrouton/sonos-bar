// SonoBar/Views/BrowseView.swift
import SwiftUI
import SonoBarKit

enum BrowseSegment: String, CaseIterable {
    case favorites = "Favorites"
    case playlists = "Playlists"
    case queue = "Queue"
}

struct BrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var segment: BrowseSegment = .favorites
    @State private var searchText = ""

    private var filteredItems: [ContentItem] {
        if searchText.isEmpty { return appState.contentItems }
        return appState.contentItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
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

            // Segment picker
            Picker("", selection: $segment) {
                ForEach(BrowseSegment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Content
            if let error = appState.contentError {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Retry") { Task { await loadContent() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if segment == .favorites {
                ContentGridView(items: filteredItems) { item in
                    Task { await appState.playItem(item) }
                }
            } else {
                ContentListView(
                    items: filteredItems,
                    currentTrackURI: segment == .queue ? appState.playbackState.currentTrack?.uri : nil
                ) { item in
                    Task {
                        if segment == .queue {
                            // Jump to track in queue
                            guard let idx = appState.contentItems.firstIndex(where: { $0.id == item.id }) else { return }
                            try? await appState.activeController?.seek(to: "\(idx + 1)")
                            await appState.refreshPlayback()
                        } else {
                            await appState.playItem(item)
                        }
                    }
                }
            }
        }
        .onAppear { Task { await loadContent() } }
        .onChange(of: segment) { _, _ in
            searchText = ""
            Task { await loadContent() }
        }
    }

    private var emptyMessage: String {
        switch segment {
        case .favorites: return "No favorites found"
        case .playlists: return "No playlists"
        case .queue: return "Queue is empty"
        }
    }

    private func loadContent() async {
        switch segment {
        case .favorites: await appState.browseFavorites()
        case .playlists: await appState.browsePlaylists()
        case .queue: await appState.browseQueue()
        }
    }
}
