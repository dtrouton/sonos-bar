/// Browses Sonos ContentDirectory for favorites, playlists, and queue.
public enum ContentBrowser {

    /// Browses Sonos Favorites (ObjectID: FV:2).
    public static func browseFavorites(client: SOAPClient) async throws -> [ContentItem] {
        try await browse(client: client, objectID: "FV:2")
    }

    /// Browses Sonos Playlists (ObjectID: SQ:).
    public static func browsePlaylists(client: SOAPClient) async throws -> [ContentItem] {
        try await browse(client: client, objectID: "SQ:")
    }

    /// Browses the current queue (ObjectID: Q:0).
    public static func browseQueue(client: SOAPClient) async throws -> [ContentItem] {
        try await browse(client: client, objectID: "Q:0")
    }

    /// Plays a content item by setting its URI and starting playback.
    public static func playItem(client: SOAPClient, item: ContentItem) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "SetAVTransportURI",
            params: [
                ("InstanceID", "0"),
                ("CurrentURI", item.resourceURI),
                ("CurrentURIMetaData", item.rawDIDL)
            ]
        )
        _ = try await client.callAction(
            service: .avTransport,
            action: "Play",
            params: [("InstanceID", "0"), ("Speed", "1")]
        )
    }

    // MARK: - Private

    private static func browse(client: SOAPClient, objectID: String) async throws -> [ContentItem] {
        let result = try await client.callAction(
            service: .contentDirectory,
            action: "Browse",
            params: [
                ("ObjectID", objectID),
                ("BrowseFlag", "BrowseDirectChildren"),
                ("Filter", "dc:title,res,upnp:albumArtURI,upnp:class,dc:creator"),
                ("StartingIndex", "0"),
                ("RequestedCount", "100"),
                ("SortCriteria", "")
            ]
        )
        guard let didlXML = result["Result"] else { return [] }
        return try DIDLParser.parse(didlXML)
    }
}
