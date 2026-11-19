// MusicKitDiscoveryProvider.swift
// SonoBarKit
//
// THE ONLY FILE THAT IMPORTS MusicKit. Wraps MusicKit catalog search + library
// requests into the app's AppleMusic* value types. Not unit-tested — exercised by
// manual QA on a real Mac with a signed-in Apple Music account.

import Foundation
import MusicKit

public final class MusicKitDiscoveryProvider: MusicDiscoveryProviding, @unchecked Sendable {

    public init() {}

    public func currentAuthStatus() -> MusicAuthStatus {
        Self.map(MusicAuthorization.currentStatus)
    }

    public func requestAuthorization() async -> MusicAuthStatus {
        Self.map(await MusicAuthorization.request())
    }

    private static func map(_ status: MusicAuthorization.Status) -> MusicAuthStatus {
        switch status {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    // MARK: - Catalog search

    public func search(_ term: String) async throws -> AppleMusicSearchResults {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self])
        request.limit = 25
        let response: MusicCatalogSearchResponse
        do {
            response = try await request.response()
        } catch {
            throw AppleMusicError.networkError
        }
        return AppleMusicSearchResults(
            tracks: response.songs.map(Self.track(from:)),
            albums: response.albums.map(Self.album(from:)),
            artists: response.artists.map { AppleMusicArtist(id: $0.id.rawValue, name: $0.name) }
        )
    }

    // MARK: - Library

    // All MusicKit failures collapse to .networkError; auth state is handled separately via
    // requestAuthorization(), and no caller currently distinguishes auth vs network errors here.

    public func libraryPlaylists() async throws -> [AppleMusicPlaylist] {
        do {
            let data = try await Self.libraryAPIData("/v1/me/library/playlists?limit=100")
            return AppleMusicLibraryAPIParser.playlists(from: data)
        } catch { throw AppleMusicError.networkError }
    }

    /// Performs a raw Apple Music library API GET via MusicKit's authenticated transport.
    private static func libraryAPIData(_ path: String) async throws -> Data {
        guard let url = URL(string: "https://api.music.apple.com" + path) else {
            throw AppleMusicError.invalidResponse
        }
        return try await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data
    }

    public func libraryAlbums() async throws -> [AppleMusicAlbum] {
        do {
            let response = try await MusicLibraryRequest<Album>().response()
            return await Self.enrichArtwork(response.items.map(Self.album(from:)))
        } catch { throw AppleMusicError.networkError }
    }

    public func librarySongs() async throws -> [AppleMusicTrack] {
        do {
            let response = try await MusicLibraryRequest<Song>().response()
            return await Self.enrichArtwork(response.items.map(Self.track(from:)))
        } catch { throw AppleMusicError.networkError }
    }

    public func playlistTracks(playlistId: String) async throws -> [AppleMusicTrack] {
        do {
            if playlistId.hasPrefix("pl.") {
                // Mirrored playlist → catalog tracks (catalog song ids, https art).
                let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(playlistId))
                guard let playlist = try await request.response().items.first else { return [] }
                let detailed = try await playlist.with([.tracks])
                return (detailed.tracks ?? []).compactMap(Self.track(from:))
            } else {
                // Library-only playlist (p.xxx) → library API tracks.
                let data = try await Self.libraryAPIData("/v1/me/library/playlists/\(playlistId)/tracks?limit=100")
                return AppleMusicLibraryAPIParser.tracks(from: data)
            }
        } catch { throw AppleMusicError.networkError }
    }

    public func albumTracks(albumId: String) async throws -> [AppleMusicTrack] {
        do {
            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(albumId))
            guard let album = try await request.response().items.first else { return [] }
            let detailed = try await album.with([.tracks])
            return (detailed.tracks ?? []).compactMap(Self.track(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack] {
        do {
            let request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(artistId))
            guard let artist = try await request.response().items.first else { return [] }
            let detailed = try await artist.with([.topSongs])
            return (detailed.topSongs ?? []).map(Self.track(from:))
        } catch { throw AppleMusicError.networkError }
    }

    // MARK: - Mappers

    private static func track(from song: Song) -> AppleMusicTrack {
        AppleMusicTrack(
            id: catalogID(for: song) ?? song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            // MusicKit doesn't expose an album id on Song without an extra .with([.albums]) fetch
            albumId: nil,
            artworkURL: httpsArt(song.artwork?.url(width: 600, height: 600)),
            durationSec: song.duration.map { Int($0) }
        )
    }

    private static func track(from track: Track) -> AppleMusicTrack? {
        switch track {
        case .song(let s): return self.track(from: s)
        case .musicVideo: return nil        // not playable on Sonos via the song URI path
        @unknown default: return nil
        }
    }

    private static func album(from album: Album) -> AppleMusicAlbum {
        // Like playlists, a library album's MusicKit id is a library id Sonos can't use; the
        // catalog album id (numeric) lives in playParameters. Resolving it fixes both artwork
        // enrichment and Sonos playback (x-rincon-cpcontainer:1004206calbum%3a<catalogId>).
        let ppData = album.playParameters.flatMap { try? playParamsEncoder.encode($0) }
        let catalogId = AppleMusicCatalogIDResolver.catalogID(playParametersJSON: ppData)
        return AppleMusicAlbum(
            id: catalogId ?? album.id.rawValue,
            title: album.title,
            artist: album.artistName,
            artworkURL: httpsArt(album.artwork?.url(width: 600, height: 600)),
            trackCount: album.trackCount
        )
    }

    private static let playParamsEncoder = JSONEncoder()

    /// Encodes the song's PlayParameters to JSON and resolves the Sonos-playable catalog id.
    private static func catalogID(for song: Song) -> String? {
        guard let pp = song.playParameters,
              let data = try? playParamsEncoder.encode(pp) else { return nil }
        return AppleMusicCatalogIDResolver.catalogID(playParametersJSON: data)
    }

    // MARK: - Artwork

    /// MusicKit returns `musicKit://` URLs for library-item artwork, which a plain image view
    /// can't load. Keep only http(s) URLs (catalog artwork); library art is filled in by the
    /// catalog-lookup enrichers below.
    private static func httpsArt(_ url: URL?) -> URL? {
        guard let scheme = url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Fetches https artwork for catalog albums by numeric id (one batched request).
    static func enrichArtwork(_ albums: [AppleMusicAlbum]) async -> [AppleMusicAlbum] {
        let ids = albums.filter { $0.artworkURL == nil && Int($0.id) != nil }.map(\.id)
        guard !ids.isEmpty,
              let resp = try? await MusicCatalogResourceRequest<Album>(matching: \.id, memberOf: ids.map { MusicItemID($0) }).response()
        else { return albums }
        var art: [String: URL] = [:]
        for a in resp.items { if let u = a.artwork?.url(width: 600, height: 600) { art[a.id.rawValue] = u } }
        guard !art.isEmpty else { return albums }
        return albums.map { a in
            guard let u = art[a.id] else { return a }
            return AppleMusicAlbum(id: a.id, title: a.title, artist: a.artist,
                                   artworkURL: u, trackCount: a.trackCount)
        }
    }

    /// Fetches https artwork for catalog songs by numeric id (one batched request).
    static func enrichArtwork(_ tracks: [AppleMusicTrack]) async -> [AppleMusicTrack] {
        let ids = tracks.filter { $0.artworkURL == nil && Int($0.id) != nil }.map(\.id)
        guard !ids.isEmpty,
              let resp = try? await MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids.map { MusicItemID($0) }).response()
        else { return tracks }
        var art: [String: URL] = [:]
        for s in resp.items { if let u = s.artwork?.url(width: 600, height: 600) { art[s.id.rawValue] = u } }
        guard !art.isEmpty else { return tracks }
        return tracks.map { t in
            guard let u = art[t.id] else { return t }
            return AppleMusicTrack(id: t.id, title: t.title, artist: t.artist, album: t.album,
                                   albumId: t.albumId, artworkURL: u, durationSec: t.durationSec)
        }
    }
}
