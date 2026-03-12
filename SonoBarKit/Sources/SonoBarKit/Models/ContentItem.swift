/// A content item from the Sonos ContentDirectory (favorite, playlist, or queue track).
public struct ContentItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let albumArtURI: String?
    public let resourceURI: String
    public let rawDIDL: String
    public let itemClass: String
    public let description: String?

    public init(
        id: String,
        title: String,
        albumArtURI: String? = nil,
        resourceURI: String,
        rawDIDL: String,
        itemClass: String,
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.albumArtURI = albumArtURI
        self.resourceURI = resourceURI
        self.rawDIDL = rawDIDL
        self.itemClass = itemClass
        self.description = description
    }

    /// Whether this item is a container (playlist, album) vs a single track.
    public var isContainer: Bool {
        itemClass.hasPrefix("object.container")
    }
}
