// SonoBar/Persistence/ArtworkCache.swift
import Foundation
import AppKit

/// Disk-based LRU cache for album artwork.
final class ArtworkCache {
    private let cacheDir: URL
    private let maxSizeBytes: Int

    init(maxSizeMB: Int = 50) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDir = caches.appendingPathComponent("SonoBar/artwork", isDirectory: true)
        self.maxSizeBytes = maxSizeMB * 1024 * 1024
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Returns cached image for a URL, or nil if not cached.
    func get(for urlString: String) -> NSImage? {
        let file = cacheDir.appendingPathComponent(cacheKey(urlString))
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Touch for LRU
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: file.path
        )
        return NSImage(data: data)
    }

    /// Stores image data for a URL.
    func set(_ data: Data, for urlString: String) {
        let file = cacheDir.appendingPathComponent(cacheKey(urlString))
        try? data.write(to: file)
        evictIfNeeded()
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
