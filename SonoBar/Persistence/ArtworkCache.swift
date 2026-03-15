// SonoBar/Persistence/ArtworkCache.swift
import Foundation
import AppKit

/// Two-tier cache for album artwork: in-memory NSCache + disk LRU.
final class ArtworkCache {
    /// Shared instance for all artwork loading across the app.
    static let shared = ArtworkCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDir: URL
    private let maxSizeBytes: Int

    init(maxSizeMB: Int = 50) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDir = caches.appendingPathComponent("SonoBar/artwork", isDirectory: true)
        self.maxSizeBytes = maxSizeMB * 1024 * 1024
        memoryCache.countLimit = 200
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Returns cached image for a URL, or nil if not cached.
    func get(for urlString: String) -> NSImage? {
        let key = cacheKey(urlString)

        // Check memory first
        if let image = memoryCache.object(forKey: key as NSString) {
            return image
        }

        // Fall back to disk
        let file = cacheDir.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: file),
              let image = NSImage(data: data) else { return nil }
        // Touch for LRU
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: file.path
        )
        // Promote to memory cache
        memoryCache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Stores image data for a URL.
    func set(_ data: Data, for urlString: String) {
        let key = cacheKey(urlString)
        let file = cacheDir.appendingPathComponent(key)
        try? data.write(to: file)
        if let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: key as NSString)
        }
        evictIfNeeded()
    }

    /// Fetches an image from cache or network. Returns nil on failure.
    func image(for urlString: String) async -> NSImage? {
        if let cached = get(for: urlString) { return cached }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        set(data, for: urlString)
        return NSImage(data: data)
    }

    private func cacheKey(_ urlString: String) -> String {
        let hash = urlString.utf8.reduce(into: UInt64(5381)) { $0 = $0 &* 33 &+ UInt64($1) }
        return String(hash, radix: 16)
    }

    private func evictIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let totalSize = files.compactMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)

        guard totalSize > maxSizeBytes else { return }

        // Sort by modification date, oldest first
        let sorted = files.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 < d2
        }

        var remaining = totalSize
        for file in sorted {
            guard remaining > maxSizeBytes else { break }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: file)
            remaining -= size
        }
    }
}
