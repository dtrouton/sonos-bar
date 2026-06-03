import Foundation
@testable import SonoBarKit

/// Scriptable MusicDiscoveryProviding for unit tests and AppState wiring.
final class FakeMusicDiscoveryProvider: MusicDiscoveryProviding, @unchecked Sendable {
    var authStatus: MusicAuthStatus = .authorized
    var searchResult: AppleMusicSearchResults =
        AppleMusicSearchResults(tracks: [], albums: [], artists: [])
    var playlists: [AppleMusicPlaylist] = []
    var albums: [AppleMusicAlbum] = []
    var songs: [AppleMusicTrack] = []
    var playlistTracksById: [String: [AppleMusicTrack]] = [:]
    var albumTracksById: [String: [AppleMusicTrack]] = [:]
    var artistTopTracksById: [String: [AppleMusicTrack]] = [:]
    var errorToThrow: AppleMusicError?

    func currentAuthStatus() -> MusicAuthStatus { authStatus }
    func requestAuthorization() async -> MusicAuthStatus { authStatus }

    func search(_ term: String) async throws -> AppleMusicSearchResults {
        if let e = errorToThrow { throw e }
        return searchResult
    }
    func libraryPlaylists() async throws -> [AppleMusicPlaylist] {
        if let e = errorToThrow { throw e }
        return playlists
    }
    func libraryAlbums() async throws -> [AppleMusicAlbum] {
        if let e = errorToThrow { throw e }
        return albums
    }
    func librarySongs() async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return songs
    }
    func playlistTracks(playlistId: String) async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return playlistTracksById[playlistId] ?? []
    }
    func albumTracks(albumId: String) async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return albumTracksById[albumId] ?? []
    }
    func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack] {
        if let e = errorToThrow { throw e }
        return artistTopTracksById[artistId] ?? []
    }
}
