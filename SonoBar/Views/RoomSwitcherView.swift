// SonoBar/Views/RoomSwitcherView.swift
import SwiftUI

struct RoomSwitcherView: View {
    // Placeholder data until wired to DeviceManager
    struct RoomItem: Identifiable {
        let id: String
        let name: String
        let status: String
        let isPlaying: Bool
        let isActive: Bool
        let groupBadge: String?
        let icon: String
    }

    @State private var rooms: [RoomItem] = []
    var onSelectRoom: ((String) -> Void)?
    var onUngroup: ((String) -> Void)?

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

            if rooms.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hifispeaker.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No Sonos speakers found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Button("Refresh") { /* trigger SSDP scan */ }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rooms) { room in
                            roomRow(room)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func roomRow(_ room: RoomItem) -> some View {
        Button {
            onSelectRoom?(room.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: room.icon)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(room.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(room.status)
                        .font(.system(size: 11))
                        .foregroundColor(room.isPlaying ? .accentColor : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let badge = room.groupBadge {
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
            .background(room.isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cornerRadius(8)
        .contextMenu {
            if room.groupBadge != nil {
                Button("Ungroup") { onUngroup?(room.id) }
            }
        }
    }
}
