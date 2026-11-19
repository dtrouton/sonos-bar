// SonoBar/Views/BrowseView.swift
import SwiftUI
import SonoBarKit

enum BrowseSegment: String, CaseIterable {
    case recents = "Recents"
    case plex = "Plex"
    case audible = "Audible"
    case appleMusic = "Apple Music"
}

struct BrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var segment: BrowseSegment = .recents
    @State private var searchText = ""

    private var filteredItems: [ContentItem] {
        if searchText.isEmpty { return appState.recentItems }
        return appState.recentItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            roomPicker
            // Segment picker
            Picker("", selection: $segment) {
                ForEach(BrowseSegment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            switch segment {
            case .recents:
                recentsContent
            case .plex:
                PlexBrowseView()
            case .audible:
                AudibleBrowseView()
            case .appleMusic:
                AppleMusicSearchView()
            }
        }
    }

    private var roomPicker: some View {
        let activeRoom = appState.deviceManager.activeDevice
        let rooms = appState.deviceManager.devices
        let isGrouped = activeRoom.flatMap { appState.deviceManager.group(for: $0.uuid) }?.isStandalone == false
        return HStack(spacing: 6) {
            Text("Play in")
                .foregroundStyle(.secondary)
            Menu {
                ForEach(rooms) { room in
                    Button {
                        appState.selectRoom(uuid: room.uuid)
                    } label: {
                        if room.uuid == activeRoom?.uuid {
                            Label(room.roomName, systemImage: "checkmark")
                        } else {
                            Text(room.roomName)
                        }
                    }
                }
            } label: {
                Text(activeRoom?.roomName ?? (rooms.isEmpty ? "No Sonos rooms" : "Choose a room"))
                    .lineLimit(1)
            }
            .disabled(rooms.isEmpty)
            .controlSize(.small)
            .accessibilityLabel("Playback room")
            .accessibilityValue(activeRoom?.roomName ?? "No room selected")

            if isGrouped {
                Image(systemName: "speaker.2")
                    .foregroundStyle(.secondary)
                    .help("Playback goes to this room's Sonos group.")
                    .accessibilityLabel("Grouped playback")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Recents Content

    private var recentsContent: some View {
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
            .padding(.top, 6)
            .padding(.bottom, 8)

            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No recents yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentGridView(items: filteredItems) { item in
                    Task { await appState.playItem(item) }
                }
            }
        }
    }
}
