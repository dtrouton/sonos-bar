// SonoBar/AppDelegate.swift
import AppKit
import SwiftUI
import SonoBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var isBrowseExpanded = false
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: "SonoBar")
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.behavior = .transient
        let hostingController = NSHostingController(
            rootView: PopoverContentView { [weak self] expanded in
                self?.isBrowseExpanded = expanded
                self?.resizePopover()
            }
            .environment(appState)
        )
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController
        resizePopover()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        Task {
            await appState.startDiscovery()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            appState.mediaKeyController.deactivate()
        } else {
            resizePopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            appState.mediaKeyController.activate(
                track: appState.playbackState.currentTrack,
                transportState: appState.playbackState.transportState
            )
        }
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        resizePopover()
    }

    private func resizePopover() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let size = PopoverSizing.size(expandedBrowse: isBrowseExpanded, fitting: screen?.visibleFrame.size)
        if popover.contentSize != size {
            popover.contentSize = size
        }
    }
}
