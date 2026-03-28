import Foundation

// MARK: - AudibleBook

/// An audiobook or podcast from the Audible API.
public struct AudibleBook: Identifiable, Sendable {
    public let asin: String
    public let title: String
    public let author: String
    public let narrator: String?
    public let coverURL: String?
    public let durationMs: Int
    public let purchaseDate: Date?
    public let isPodcast: Bool
    public let episodeCount: Int?

    public var id: String { asin }
}

extension AudibleBook: Codable {
    enum CodingKeys: String, CodingKey {
        case asin
        case title
        case authors
        case narrators
        case productImages = "product_images"
        case durationMs = "runtime_length_ms"
        case purchaseDate = "purchase_date"
        case contentDeliveryType = "content_delivery_type"
        case contentType = "content_type"
        case episodeCount = "episode_count"
    }

    /// Intermediate type for the `authors` / `narrators` arrays.
    private struct PersonItem: Codable {
        let name: String
    }

    /// Intermediate type for `product_images` which maps size strings to URLs.
    private struct ProductImages: Codable {
        let size500: String?

        enum CodingKeys: String, CodingKey {
            case size500 = "500"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asin = try container.decode(String.self, forKey: .asin)
        title = try container.decode(String.self, forKey: .title)

        let authors = try container.decodeIfPresent([PersonItem].self, forKey: .authors)
        author = authors?.first?.name ?? "Unknown"

        let narrators = try container.decodeIfPresent([PersonItem].self, forKey: .narrators)
        narrator = narrators?.first?.name

        let images = try container.decodeIfPresent(ProductImages.self, forKey: .productImages)
        coverURL = images?.size500

        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0

        if let dateString = try container.decodeIfPresent(String.self, forKey: .purchaseDate) {
            let formatter = ISO8601DateFormatter()
            purchaseDate = formatter.date(from: dateString)
        } else {
            purchaseDate = nil
        }

        let deliveryType = try container.decodeIfPresent(String.self, forKey: .contentDeliveryType) ?? ""
        let cType = try container.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        isPodcast = deliveryType == "PodcastParent" || deliveryType == "Periodical" || cType == "Podcast"
        episodeCount = try container.decodeIfPresent(Int.self, forKey: .episodeCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(asin, forKey: .asin)
        try container.encode(title, forKey: .title)
        try container.encode([PersonItem(name: author)], forKey: .authors)
        if let narrator {
            try container.encode([PersonItem(name: narrator)], forKey: .narrators)
        }
        if let coverURL {
            try container.encode(ProductImages(size500: coverURL), forKey: .productImages)
        }
        try container.encode(durationMs, forKey: .durationMs)
        if isPodcast {
            try container.encode("PodcastParent", forKey: .contentDeliveryType)
        }
        try container.encodeIfPresent(episodeCount, forKey: .episodeCount)
        if let purchaseDate {
            let formatter = ISO8601DateFormatter()
            try container.encode(formatter.string(from: purchaseDate), forKey: .purchaseDate)
        }
    }
}

// MARK: - AudibleChapter

/// A chapter within an Audible audiobook.
public struct AudibleChapter: Identifiable, Sendable, Codable {
    public let index: Int
    public let title: String
    public let startOffsetMs: Int
    public let durationMs: Int

    public var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case title
        case startOffsetMs = "start_offset_ms"
        case durationMs = "length_ms"
    }

    public init(index: Int, title: String, startOffsetMs: Int, durationMs: Int) {
        self.index = index
        self.title = title
        self.startOffsetMs = startOffsetMs
        self.durationMs = durationMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        startOffsetMs = try container.decode(Int.self, forKey: .startOffsetMs)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        // index is assigned externally when parsing the array
        index = 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(startOffsetMs, forKey: .startOffsetMs)
        try container.encode(durationMs, forKey: .durationMs)
    }
}

// MARK: - AudibleChapterResponse

/// Wrapper for the nested chapter response JSON structure.
public struct AudibleChapterResponse: Sendable, Codable {
    public let chapters: [AudibleChapter]

    enum OuterKeys: String, CodingKey {
        case contentMetadata = "content_metadata"
    }

    enum ChapterInfoKeys: String, CodingKey {
        case chapterInfo = "chapter_info"
    }

    enum ChaptersKeys: String, CodingKey {
        case chapters
    }

    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: OuterKeys.self)
        let chapterInfoContainer = try outer.nestedContainer(keyedBy: ChapterInfoKeys.self, forKey: .contentMetadata)
        let chaptersContainer = try chapterInfoContainer.nestedContainer(keyedBy: ChaptersKeys.self, forKey: .chapterInfo)
        let rawChapters = try chaptersContainer.decode([AudibleChapter].self, forKey: .chapters)

        // Assign correct indices based on array position
        chapters = rawChapters.enumerated().map { index, chapter in
            AudibleChapter(
                index: index,
                title: chapter.title,
                startOffsetMs: chapter.startOffsetMs,
                durationMs: chapter.durationMs
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var outer = encoder.container(keyedBy: OuterKeys.self)
        var chapterInfoContainer = outer.nestedContainer(keyedBy: ChapterInfoKeys.self, forKey: .contentMetadata)
        var chaptersContainer = chapterInfoContainer.nestedContainer(keyedBy: ChaptersKeys.self, forKey: .chapterInfo)
        try chaptersContainer.encode(chapters, forKey: .chapters)
    }
}

// MARK: - AudibleListeningPosition

/// A listening position for an Audible audiobook.
public struct AudibleListeningPosition: Sendable, Codable {
    public let asin: String
    public let positionMs: Int

    enum CodingKeys: String, CodingKey {
        case asin
        case positionMs = "last_position_ms"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asin = try container.decode(String.self, forKey: .asin)
        positionMs = try container.decodeIfPresent(Int.self, forKey: .positionMs) ?? 0
    }
}

// MARK: - AudibleListeningPositionResponse

/// Wrapper for the listening positions API response.
public struct AudibleListeningPositionResponse: Sendable, Codable {
    public let items: [AudibleListeningPosition]

    enum CodingKeys: String, CodingKey {
        case items
        case lastPositions = "last_positions"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try both possible response shapes
        if let items = try? container.decode([AudibleListeningPosition].self, forKey: .items) {
            self.items = items
        } else if let items = try? container.decode([AudibleListeningPosition].self, forKey: .lastPositions) {
            self.items = items
        } else {
            self.items = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}
