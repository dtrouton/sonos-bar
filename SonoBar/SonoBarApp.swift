// SonoBar/SonoBarApp.swift
import SwiftUI

@main
struct SonoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No window — menu bar only
        Settings {
            EmptyView()
        }
    }
}
