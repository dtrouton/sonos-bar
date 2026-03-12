// SonoBar/Views/RoomSwitcherView.swift
import SwiftUI
import SonoBarKit

struct RoomSwitcherView: View {
    @Environment(AppState.self) private var appState

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
    }

    private func roomRow(_ device: SonosDevice) -> some View {
        let isActive = device.uuid == appState.deviceManager.activeDevice?.uuid
        let group = appState.deviceManager.group(for: device.uuid)
        let isGrouped = group.map { !$0.isStandalone } ?? false
        let groupBadge: String? = isGrouped ? "\(group?.members.count ?? 0)" : nil
        let icon = device.modelName.lowercased().contains("sub") ? "hifispeaker.and.appletv" : "hifispeaker.fill"

        return Button {
            appState.selectRoom(uuid: device.uuid)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.roomName)
                        .font(.system(size: 13, weight: .medium))
                    Text(statusText(for: device))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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
                    Task {
                        let client = SOAPClient(host: device.ip)
                        try? await GroupManager.ungroup(client: client)
                        await appState.startDiscovery()
                    }
                }
            }
        }
    }

    private func statusText(for device: SonosDevice) -> String {
        if !device.isReachable {
            return "Offline"
        }
        if device.uuid == appState.deviceManager.activeDevice?.uuid {
            switch appState.playbackState.transportState {
            case .playing:
                return appState.playbackState.currentTrack?.title ?? "Playing"
            case .pausedPlayback:
                return "Paused"
            case .stopped:
                return "Idle"
            case .transitioning:
                return "Loading..."
            }
        }
        return device.modelName.isEmpty ? "Sonos" : device.modelName
    }
}
