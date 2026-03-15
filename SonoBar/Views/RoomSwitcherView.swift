// SonoBar/Views/RoomSwitcherView.swift
import SwiftUI
import SonoBarKit

struct RoomSwitcherView: View {
    @Environment(AppState.self) private var appState
    var onRoomSelected: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rooms")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if appState.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching for speakers...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.deviceManager.devices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hifispeaker.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No Sonos speakers found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Button("Refresh") {
                        Task { await appState.startDiscovery() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.deviceManager.devices) { device in
                            roomRow(device)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onAppear {
            Task { await appState.refreshAllRooms() }
        }
    }

    private func roomRow(_ device: SonosDevice) -> some View {
        let isActive = device.uuid == appState.deviceManager.activeDevice?.uuid
        let group = appState.deviceManager.group(for: device.uuid)
        let isGrouped = group.map { !$0.isStandalone } ?? false
        let groupBadge: String? = isGrouped ? "\(group?.members.count ?? 0)" : nil
        let summary = appState.roomStates[device.uuid]

        return Button {
            appState.selectRoom(uuid: device.uuid)
            onRoomSelected()
        } label: {
            HStack(spacing: 12) {
                RoomArtworkView(summary: summary, speakerIP: appState.deviceManager.coordinatorIP(for: device.uuid))

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.roomName)
                        .font(.system(size: 13, weight: .medium))
                    Text(statusText(for: device))
                        .font(.system(size: 11))
                        .foregroundColor(appState.roomStates[device.uuid]?.transportState == .playing ? .accentColor : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let badge = groupBadge {
                    Text(badge)
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cornerRadius(8)
        .contextMenu {
            if isGrouped {
                Button("Ungroup") {
                    Task { await appState.ungroupDevice(uuid: device.uuid) }
                }
            }
        }
    }

    private func statusText(for device: SonosDevice) -> String {
        if !device.isReachable { return "Offline" }
        guard let summary = appState.roomStates[device.uuid] else {
            return device.modelName.isEmpty ? "Sonos" : device.modelName
        }
        // Detect source from URI
        if let uri = summary.trackURI {
            if uri.hasPrefix("x-sonos-htastream:") {
                return summary.transportState == .playing ? "TV" : "TV (paused)"
            }
            if uri.hasPrefix("x-rincon-stream:") {
                return summary.transportState == .playing ? "Line-In" : "Line-In (paused)"
            }
        }

        switch summary.transportState {
        case .playing:
            if let title = summary.trackTitle {
                if let artist = summary.trackArtist {
                    return "\(artist) \u{2014} \(title)"
                }
                return title
            }
            return "Playing"
        case .pausedPlayback:
            return "Paused"
        case .stopped:
            return "Idle"
        case .transitioning:
            return "Loading..."
        case .noMediaPresent:
            return "Idle"
        }
    }
}

/// Shows album art for a room, or a contextual icon (TV, speaker) as fallback.
private struct RoomArtworkView: View {
    let summary: RoomSummary?
    let speakerIP: String?
    @State private var image: NSImage?

    private var fallbackIcon: String {
        guard let uri = summary?.trackURI else { return "hifispeaker.fill" }
        if uri.hasPrefix("x-sonos-htastream:") { return "tv" }
        if uri.hasPrefix("x-rincon-stream:") { return "cable.connector" }
        return "hifispeaker.fill"
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay(
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: summary?.albumArtURI) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> NSImage? {
        guard let artURI = summary?.albumArtURI, !artURI.isEmpty else { return nil }

        let urlString: String
        if artURI.hasPrefix("http://") || artURI.hasPrefix("https://") {
            urlString = artURI
        } else {
            guard let ip = speakerIP else { return nil }
            urlString = "http://\(ip):1400\(artURI)"
        }

        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        return NSImage(data: data)
    }
}
