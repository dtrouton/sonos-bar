// SonoBar/Persistence/SettingsStore.swift
import Foundation

/// Persists user settings and cached state in UserDefaults.
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Active Room

    var activeDeviceUUID: String? {
        get { defaults.string(forKey: "activeDeviceUUID") }
        set { defaults.set(newValue, forKey: "activeDeviceUUID") }
    }

    // MARK: - Cached Speaker List

    var cachedSpeakers: [[String: String]] {
        get { defaults.array(forKey: "cachedSpeakers") as? [[String: String]] ?? [] }
        set { defaults.set(newValue, forKey: "cachedSpeakers") }
    }

    func saveSpeakers(_ devices: [(uuid: String, ip: String, roomName: String)]) {
        cachedSpeakers = devices.map {
            ["uuid": $0.uuid, "ip": $0.ip, "roomName": $0.roomName]
        }
    }

    func loadCachedSpeakers() -> [(uuid: String, ip: String, roomName: String)] {
        cachedSpeakers.compactMap { dict in
            guard let uuid = dict["uuid"], let ip = dict["ip"], let room = dict["roomName"] else { return nil }
            return (uuid: uuid, ip: ip, roomName: room)
        }
    }

    // MARK: - Launch at Login

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
}
