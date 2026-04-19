// SonoBar/AppDelegate.swift
import AppKit
import SwiftUI
import SonoBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: "SonoBar")
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environment(appState)
        )
        Task {
            await appState.startDiscovery()
            #if DEBUG
            await runAppleMusicSpikeIfEligible()
            #endif
        }
    }

    #if DEBUG
    /// One-shot spike run — fires after discovery completes against the active speaker's
    /// SOAPClient. Writes everything to Console.app for capture.
    private func runAppleMusicSpikeIfEligible() async {
        // Small delay to let zone topology settle.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard let device = appState.deviceManager.activeDevice else {
            print("[Spike] No active device. Select a room in the popover, relaunch to re-run.")
            return
        }
        let client = SOAPClient(host: device.ip)
        await AppleMusicSpike.run(client: client)
    }
    #endif

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            appState.mediaKeyController.deactivate()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            appState.mediaKeyController.activate(
                track: appState.playbackState.currentTrack,
                transportState: appState.playbackState.transportState
            )
        }
    }
}
