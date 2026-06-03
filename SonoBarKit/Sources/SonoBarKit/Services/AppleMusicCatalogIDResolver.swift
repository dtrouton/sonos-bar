// AppleMusicCatalogIDResolver.swift
// SonoBarKit
//
// Resolves a MusicKit PlayParameters JSON blob to a Sonos-playable catalog song id.
// Catalog items: "id" is already the store id. Library items: prefer "catalogId".
// Library-only (uploaded/matched-without-catalog) items have no catalog id and are
// not playable on Sonos.

import Foundation

public enum AppleMusicCatalogIDResolver {

    private struct PlayParametersJSON: Decodable {
        let id: String?
        let catalogId: String?
        let isLibrary: Bool?
    }

    /// Returns the catalog song id usable in `AppleMusicURIs.trackURI`, or nil if none.
    public static func catalogID(playParametersJSON: Data?) -> String? {
        guard let data = playParametersJSON,
              let pp = try? JSONDecoder().decode(PlayParametersJSON.self, from: data)
        else { return nil }

        if let catalogId = pp.catalogId, !catalogId.isEmpty {
            return catalogId
        }
        // Catalog item: id is the store id. Library item without catalogId: not playable.
        if pp.isLibrary == true { return nil }
        if let id = pp.id, !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) { return id }
        return nil
    }
}
