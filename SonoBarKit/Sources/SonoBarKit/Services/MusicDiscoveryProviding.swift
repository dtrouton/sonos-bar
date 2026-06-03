// MusicDiscoveryProviding.swift
// SonoBarKit
//
// The seam isolating MusicKit from the rest of the app. The only concrete
// implementation that imports MusicKit is MusicKitDiscoveryProvider; tests and
// previews use a fake. All methods return the app's own AppleMusic* value types.

public enum MusicAuthStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

public protocol MusicDiscoveryProviding: Sendable {
    func currentAuthStatus() -> MusicAuthStatus
    func requestAuthorization() async -> MusicAuthStatus

    func search(_ term: String) async throws -> AppleMusicSearchResults
    func libraryPlaylists() async throws -> [AppleMusicPlaylist]
    func libraryAlbums() async throws -> [AppleMusicAlbum]
    func librarySongs() async throws -> [AppleMusicTrack]
    func playlistTracks(playlistId: String) async throws -> [AppleMusicTrack]
    func albumTracks(albumId: String) async throws -> [AppleMusicTrack]
    func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack]
}
