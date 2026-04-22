// AppleMusicModels.swift
// SonoBarKit
//
// Value types for Apple Music content surfaced via the iTunes Search API
// and credentials extracted from Sonos favorites.

import Foundation

public struct AppleMusicTrack: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let artist: String?
    public let album: String?
    public let albumId: String?
    public let artworkURL: URL?
    public let durationSec: Int?

    public init(id: String, title: String, artist: String?, album: String?,
                albumId: String?, artworkURL: URL?, durationSec: Int?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.artworkURL = artworkURL
        self.durationSec = durationSec
    }
}

public struct AppleMusicAlbum: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let artist: String?
    public let artworkURL: URL?
    public let trackCount: Int?

    public init(id: String, title: String, artist: String?, artworkURL: URL?, trackCount: Int?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.trackCount = trackCount
    }
}

public struct AppleMusicArtist: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AppleMusicSearchResults: Sendable, Equatable {
    public let tracks: [AppleMusicTrack]
    public let albums: [AppleMusicAlbum]
    public let artists: [AppleMusicArtist]

    public init(tracks: [AppleMusicTrack], albums: [AppleMusicAlbum], artists: [AppleMusicArtist]) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
    }
}

public enum AppleMusicPlayable: Sendable, Equatable {
    case track(AppleMusicTrack)
    case album(AppleMusicAlbum)

    public var id: String {
        switch self {
        case .track(let t): return t.id
        case .album(let a): return a.id
        }
    }

    public var title: String {
        switch self {
        case .track(let t): return t.title
        case .album(let a): return a.title
        }
    }

    public var artworkURL: URL? {
        switch self {
        case .track(let t): return t.artworkURL
        case .album(let a): return a.artworkURL
        }
    }
}

/// Playback credentials extracted from a Sonos favorite. The sn and accountToken values
/// come from the speaker's live state — we do NOT construct them, because the
/// ListAvailableServices sn and the node-sonos-http-api "-0-" token are both wrong for
/// modern Apple Music linkages (see spike findings).
public struct AppleMusicCredentials: Sendable, Equatable {
    public let sn: Int
    public let accountToken: String

    public init(sn: Int, accountToken: String) {
        self.sn = sn
        self.accountToken = accountToken
    }
}

public enum AppleMusicError: Error, Sendable, Equatable {
    case notLinked
    case networkError
    case httpError(Int)
    case invalidResponse
}
