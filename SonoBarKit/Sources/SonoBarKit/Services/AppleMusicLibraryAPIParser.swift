// AppleMusicLibraryAPIParser.swift
// SonoBarKit
//
// Parses Apple Music *library* API JSON (https://api.music.apple.com/v1/me/library/...)
// into the app's value types. We use the raw library API (via MusicDataRequest) rather than
// MusicKit's typed library requests because only it exposes:
//   • the `p.xxx` library playlist id (Sonos plays un-mirrored playlists by this id), and
//   • the `globalId` (`pl.…`) catalog-mirror id (Sonos plays mirrored playlists by this), and
//   • real https artwork — including user-custom covers — which MusicKit hides behind the
//     unloadable `musicKit://` scheme.
//
// The pure parsing here is unit-tested with fixtures captured from a live account.

import Foundation

public enum AppleMusicLibraryAPIParser {

    /// Parses /v1/me/library/playlists. For each playlist:
    ///  - if it has a catalog mirror (`playParams.globalId`), `id` is that `pl.…` id and
    ///    `isLibrary` is false → Sonos catalog container form.
    ///  - otherwise `id` is the `p.xxx` library id and `isLibrary` is true → Sonos library form.
    public static func playlists(from data: Data) -> [AppleMusicPlaylist] {
        items(from: data).compactMap { item in
            guard let libraryId = item["id"] as? String else { return nil }
            let attrs = item["attributes"] as? [String: Any]
            let globalId = (attrs?["playParams"] as? [String: Any])?["globalId"] as? String
            return AppleMusicPlaylist(
                id: globalId ?? libraryId,
                name: attrs?["name"] as? String ?? "Playlist",
                curatorName: attrs?["curatorName"] as? String,
                artworkURL: artworkURL(attrs?["artwork"] as? [String: Any]),
                trackCount: (attrs?["trackCount"] as? Int),
                isLibrary: globalId == nil
            )
        }
    }

    /// Parses a library tracks payload (/v1/me/library/playlists/{id}/tracks). A track's
    /// Sonos-playable id is its catalog song id (`playParams.catalogId`); uploaded/unmatched
    /// tracks keep their non-numeric library id and render disabled in the UI.
    public static func tracks(from data: Data) -> [AppleMusicTrack] {
        items(from: data).compactMap { item in
            let attrs = item["attributes"] as? [String: Any]
            let catalogId = (attrs?["playParams"] as? [String: Any])?["catalogId"] as? String
            let id = catalogId ?? (item["id"] as? String ?? "")
            guard !id.isEmpty else { return nil }
            let durationMillis = attrs?["durationInMillis"] as? Int
            return AppleMusicTrack(
                id: id,
                title: attrs?["name"] as? String ?? "",
                artist: attrs?["artistName"] as? String,
                album: attrs?["albumName"] as? String,
                albumId: nil,
                artworkURL: artworkURL(attrs?["artwork"] as? [String: Any]),
                durationSec: durationMillis.map { $0 / 1000 }
            )
        }
    }

    // MARK: - Helpers

    static func items(from data: Data) -> [[String: Any]] {
        let json = try? JSONSerialization.jsonObject(with: data)
        return ((json as? [String: Any])?["data"] as? [[String: Any]]) ?? []
    }

    /// Apple Music artwork URLs are either a direct https URL or a template containing
    /// `{w}`/`{h}`/`{f}` placeholders. Resolve placeholders to a concrete 600x600 jpg.
    static func artworkURL(_ artwork: [String: Any]?) -> URL? {
        guard let template = artwork?["url"] as? String else { return nil }
        let resolved = template
            .replacingOccurrences(of: "{w}", with: "600")
            .replacingOccurrences(of: "{h}", with: "600")
            .replacingOccurrences(of: "{f}", with: "jpg")
        return URL(string: resolved)
    }
}
