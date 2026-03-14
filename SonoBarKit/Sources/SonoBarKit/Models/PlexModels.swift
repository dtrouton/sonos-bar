import Foundation

// MARK: - PlexLibrary

/// A Plex media library (e.g. "Music", "Audiobooks").
public struct PlexLibrary: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let type: String

    enum CodingKeys: String, CodingKey {
        case id = "key"
        case title
        case type
    }
}

// MARK: - PlexAlbum

/// A Plex album or audiobook container.
public struct PlexAlbum: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let artist: String
    public let thumbPath: String?
    public let trackCount: Int
    public let year: Int?
    public let viewOffset: Int?

    enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case artist = "parentTitle"
        case thumbPath = "thumb"
        case trackCount = "leafCount"
        case year
        case viewOffset
    }
}

// MARK: - PlexTrack

/// A Plex audio track with playback progress info.
public struct PlexTrack: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let albumTitle: String
    public let artistName: String
    public let duration: Int
    public let viewOffset: Int
    public let index: Int
    public let partKey: String
    public let thumbPath: String?
    public let lastViewedAt: Date?
}

extension PlexTrack: Codable {
    enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case albumTitle = "parentTitle"
        case artistName = "grandparentTitle"
        case duration
        case viewOffset
        case index
        case thumbPath = "thumb"
        case lastViewedAt
        case media = "Media"
    }

    /// Intermediate type for navigating the nested Media[0].Part[0].key JSON path.
    private struct MediaItem: Codable {
        let Part: [PartItem]
    }

    private struct PartItem: Codable {
        let key: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        albumTitle = try container.decode(String.self, forKey: .albumTitle)
        artistName = try container.decode(String.self, forKey: .artistName)
        duration = try container.decode(Int.self, forKey: .duration)
        viewOffset = try container.decodeIfPresent(Int.self, forKey: .viewOffset) ?? 0
        index = try container.decode(Int.self, forKey: .index)
        thumbPath = try container.decodeIfPresent(String.self, forKey: .thumbPath)

        // lastViewedAt is a Unix timestamp in the JSON
        if let timestamp = try container.decodeIfPresent(Double.self, forKey: .lastViewedAt) {
            lastViewedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            lastViewedAt = nil
        }

        // partKey is nested: Media[0].Part[0].key
        let mediaArray = try container.decode([MediaItem].self, forKey: .media)
        guard let firstMedia = mediaArray.first,
              let firstPart = firstMedia.Part.first else {
            throw DecodingError.dataCorruptedError(
                forKey: .media,
                in: container,
                debugDescription: "Expected at least one Media with one Part"
            )
        }
        partKey = firstPart.key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(albumTitle, forKey: .albumTitle)
        try container.encode(artistName, forKey: .artistName)
        try container.encode(duration, forKey: .duration)
        try container.encode(viewOffset, forKey: .viewOffset)
        try container.encode(index, forKey: .index)
        try container.encodeIfPresent(thumbPath, forKey: .thumbPath)
        if let lastViewedAt {
            try container.encode(lastViewedAt.timeIntervalSince1970, forKey: .lastViewedAt)
        }
        let mediaArray = [MediaItem(Part: [PartItem(key: partKey)])]
        try container.encode(mediaArray, forKey: .media)
    }
}

// MARK: - PlexResponse

/// Generic wrapper for Plex API responses containing a MediaContainer.
public struct PlexResponse<T: Codable>: Codable {
    public let mediaContainer: MediaContainer

    public struct MediaContainer: Codable {
        public let size: Int?
        public let directory: [T]?
        public let metadata: [T]?

        /// Returns the items from whichever key is present (Directory or Metadata).
        public var items: [T] { directory ?? metadata ?? [] }

        enum CodingKeys: String, CodingKey {
            case size
            case directory = "Directory"
            case metadata = "Metadata"
        }
    }

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}
