// ITunesSearchClient.swift
// SonoBarKit
//
// Public iTunes Search API client. No authentication required.
// https://performance-partners.apple.com/search-api
//
// trackId / collectionId / artistId values returned here are binary-compatible with
// the Sonos Apple Music URI templates used by AppleMusicURIs (verified in the Task 0
// spike via live AddURIToQueue).

import Foundation

public final class ITunesSearchClient: Sendable {
    private let country: String
    private let httpClient: HTTPClientProtocol

    public init(country: String = "US", httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.country = country
        self.httpClient = httpClient
    }

    public func search(_ term: String) async throws -> AppleMusicSearchResults {
        async let songs: [RawResult] = fetchResults(term: term, entity: "song", limit: 25)
        async let albums: [RawResult] = fetchResults(term: term, entity: "album", limit: 25)
        async let artists: [RawResult] = fetchResults(term: term, entity: "musicArtist", limit: 10)

        let (s, a, ar) = try await (songs, albums, artists)
        return AppleMusicSearchResults(
            tracks: s.compactMap(toTrack),
            albums: a.compactMap(toAlbum),
            artists: ar.compactMap(toArtist)
        )
    }

    public func albumTracks(albumId: String) async throws -> [AppleMusicTrack] {
        let results = try await fetchLookup(id: albumId, entity: "song")
        return results.compactMap(toTrack)
    }

    public func artistTopTracks(artistId: String) async throws -> [AppleMusicTrack] {
        let results = try await fetchLookup(id: artistId, entity: "song", limit: 25)
        return results.compactMap(toTrack)
    }

    // MARK: - Private

    private struct SearchResponse: Decodable {
        let resultCount: Int
        let results: [RawResult]
    }

    private struct RawResult: Decodable {
        let wrapperType: String?
        let kind: String?
        let collectionType: String?
        let artistType: String?
        let trackId: Int?
        let collectionId: Int?
        let artistId: Int?
        let artistName: String?
        let collectionName: String?
        let trackName: String?
        let artworkUrl100: String?
        let trackTimeMillis: Int?
        let trackCount: Int?
    }

    private func fetchResults(term: String, entity: String, limit: Int) async throws -> [RawResult] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]
        return try await fetch(url: comps.url!)
    }

    private func fetchLookup(id: String, entity: String, limit: Int = 200) async throws -> [RawResult] {
        var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
        comps.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]
        return try await fetch(url: comps.url!)
    }

    private func fetch(url: URL) async throws -> [RawResult] {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.send(req)
        } catch {
            throw AppleMusicError.networkError
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AppleMusicError.httpError(response.statusCode)
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data).results
        } catch {
            throw AppleMusicError.invalidResponse
        }
    }

    // MARK: - Mappers

    private func toTrack(_ r: RawResult) -> AppleMusicTrack? {
        guard r.kind == "song" || r.wrapperType == "track", let tid = r.trackId else { return nil }
        return AppleMusicTrack(
            id: String(tid),
            title: r.trackName ?? "",
            artist: r.artistName,
            album: r.collectionName,
            albumId: r.collectionId.map(String.init),
            artworkURL: upsizedArtwork(r.artworkUrl100),
            durationSec: r.trackTimeMillis.map { $0 / 1000 }
        )
    }

    private func toAlbum(_ r: RawResult) -> AppleMusicAlbum? {
        guard r.collectionType == "Album" || r.wrapperType == "collection",
              let cid = r.collectionId else { return nil }
        return AppleMusicAlbum(
            id: String(cid),
            title: r.collectionName ?? "",
            artist: r.artistName,
            artworkURL: upsizedArtwork(r.artworkUrl100),
            trackCount: r.trackCount
        )
    }

    private func toArtist(_ r: RawResult) -> AppleMusicArtist? {
        guard r.wrapperType == "artist" || r.artistType != nil, let aid = r.artistId else { return nil }
        return AppleMusicArtist(id: String(aid), name: r.artistName ?? "")
    }

    private func upsizedArtwork(_ urlStr: String?) -> URL? {
        guard let s = urlStr else { return nil }
        let upsized = s.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
        return URL(string: upsized) ?? URL(string: s)
    }
}
