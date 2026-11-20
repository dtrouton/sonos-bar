// SonoBar/Views/PopoverContentView.swift
import SwiftUI
import SonoBarKit

enum Tab {
    case nowPlaying, rooms, browse, alarms
}

enum PopoverSizing {
    static let compact = CGSize(width: 320, height: 480)
    static let expanded = CGSize(width: 600, height: 680)

    static func size(expandedBrowse: Bool, fitting visibleScreenSize: CGSize?) -> CGSize {
        let preferred = expandedBrowse ? expanded : compact
        let inset: CGFloat = 24
        guard let screen = visibleScreenSize, screen.width > inset, screen.height > inset else { return preferred }
        return CGSize(
            width: min(preferred.width, screen.width - inset),
            height: min(preferred.height, screen.height - inset)
        )
    }
}

struct PopoverContentView: View {
    let onBrowseExpansionChange: (Bool) -> Void
    @AppStorage("expandBrowsePopover") private var isBrowseExpanded = false
    @State private var selectedTab: Tab = .nowPlaying

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .nowPlaying:
                    NowPlayingView(navigateToRooms: { selectedTab = .rooms })
                case .rooms:
                    RoomSwitcherView(onRoomSelected: { selectedTab = .nowPlaying })
                case .browse:
                    BrowseView(isExpanded: $isBrowseExpanded)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedTab == .browse && isBrowseExpanded, initial: true) { _, expanded in
            onBrowseExpansionChange(expanded)
        }
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
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }
}
