// SonoBar/Views/PopoverContentView.swift
import SwiftUI
import SonoBarKit

enum Tab {
    case nowPlaying, rooms, browse, alarms
}

struct PopoverContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .nowPlaying

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .nowPlaying:
                    NowPlayingView(navigateToRooms: { selectedTab = .rooms })
                case .rooms:
                    RoomSwitcherView()
                case .browse:
                    BrowseView()
                case .alarms:
                    AlarmsView()
                }
            }

            Divider()

            HStack(spacing: 0) {
                tabButton(tab: .nowPlaying, icon: "play.fill", label: "Now")
                tabButton(tab: .rooms, icon: "house.fill", label: "Rooms")
                tabButton(tab: .browse, icon: "books.vertical.fill", label: "Browse")
                tabButton(tab: .alarms, icon: "alarm.fill", label: "Alarms")
            }
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 320, height: 450)
    }

    private func tabButton(tab: Tab, icon: String, label: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 10))
            }
            .foregroundColor(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
