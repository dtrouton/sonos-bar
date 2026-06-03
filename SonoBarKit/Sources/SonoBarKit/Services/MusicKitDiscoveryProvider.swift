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
            let response = try await MusicLibraryRequest<Playlist>().response()
            return response.items.map(Self.playlist(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func libraryAlbums() async throws -> [AppleMusicAlbum] {
        do {
            let response = try await MusicLibraryRequest<Album>().response()
            return response.items.map(Self.album(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func librarySongs() async throws -> [AppleMusicTrack] {
        do {
            let response = try await MusicLibraryRequest<Song>().response()
            return response.items.map(Self.track(from:))
        } catch { throw AppleMusicError.networkError }
    }

    public func playlistTracks(playlistId: String) async throws -> [AppleMusicTrack] {
        do {
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, equalTo: MusicItemID(playlistId))
            guard let playlist = try await request.response().items.first else { return [] }
            let detailed = try await playlist.with([.tracks])
            return (detailed.tracks ?? []).compactMap(Self.track(from:))
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
            artworkURL: song.artwork?.url(width: 600, height: 600),
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
        AppleMusicAlbum(
            id: album.id.rawValue,
            title: album.title,
            artist: album.artistName,
            artworkURL: album.artwork?.url(width: 600, height: 600),
            trackCount: album.trackCount
        )
    }

    private static func playlist(from playlist: Playlist) -> AppleMusicPlaylist {
        AppleMusicPlaylist(
            id: playlist.id.rawValue,
            name: playlist.name,
            curatorName: playlist.curatorName,
            artworkURL: playlist.artwork?.url(width: 600, height: 600),
            trackCount: nil,
            isLibrary: true  // only library playlists are fetched here
        )
    }

    private static let playParamsEncoder = JSONEncoder()

    /// Encodes the song's PlayParameters to JSON and resolves the Sonos-playable catalog id.
    private static func catalogID(for song: Song) -> String? {
        guard let pp = song.playParameters,
              let data = try? playParamsEncoder.encode(pp) else { return nil }
        return AppleMusicCatalogIDResolver.catalogID(playParametersJSON: data)
    }
}
