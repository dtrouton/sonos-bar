// PlexClient.swift
// SonoBarKit
//
// HTTP client for communicating with a Plex Media Server.
// Uses the same HTTPClientProtocol as SOAPClient for testability.

import Foundation

// MARK: - PlexError

public enum PlexError: Error, Sendable, Equatable {
    case invalidURL(String)
    case unauthorized
    case httpError(Int)
    case serverUnreachable
}

// MARK: - PlexClient

public final class PlexClient: Sendable {
    public let host: String
    public let port: Int
    private let token: String
    private let httpClient: HTTPClientProtocol

    public init(
        host: String,
        port: Int = 32400,
        token: String,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.host = host
        self.port = port
        self.token = token
        self.httpClient = httpClient
    }

    // MARK: - Libraries

    /// Fetches all library sections from the Plex server.
    public func getLibraries() async throws -> [PlexLibrary] {
        try await get("/library/sections")
    }

    // MARK: - Albums

    /// Fetches all albums in a library section (type=9 is album).
    public func getAlbums(sectionId: String) async throws -> [PlexAlbum] {
        try await get("/library/sections/\(sectionId)/all", queryItems: [
            URLQueryItem(name: "type", value: "9"),
        ])
    }

    // MARK: - Tracks

    /// Fetches all tracks for an album.
    public func getTracks(albumId: String) async throws -> [PlexTrack] {
        try await get("/library/metadata/\(albumId)/children")
    }

    // MARK: - On Deck / Continue Listening

    /// Fetches on-deck (continue listening) tracks for a library section.
    public func getOnDeck(sectionId: String) async throws -> [PlexTrack] {
        try await get("/library/sections/\(sectionId)/onDeck")
    }

    // MARK: - Recently Played

    /// Fetches recently viewed albums for a library section.
    public func getRecentlyPlayed(sectionId: String) async throws -> [PlexAlbum] {
        try await get("/library/sections/\(sectionId)/recentlyViewed")
    }

    // MARK: - Search

    /// Searches for albums matching a query, optionally within a specific section.
    public func search(query: String, sectionId: String? = nil) async throws -> [PlexAlbum] {
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "type", value: "9"),
        ]
        if let sectionId {
            queryItems.append(URLQueryItem(name: "sectionId", value: sectionId))
        }
        return try await get("/hubs/search", queryItems: queryItems)
    }

    // MARK: - Progress Reporting

    /// Reports playback progress to the Plex server for resume support.
    public func reportProgress(trackId: String, offsetMs: Int, duration: Int, state: String) async throws {
        let queryItems = [
            URLQueryItem(name: "ratingKey", value: trackId),
            URLQueryItem(name: "time", value: String(offsetMs)),
            URLQueryItem(name: "duration", value: String(duration)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "key", value: "/library/metadata/\(trackId)"),
        ]

        let url = try buildURL(path: "/:/timeline", queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        applyHeaders(&request)
        request.timeoutInterval = 5

        let (_, httpResponse) = try await sendRequest(request)
        try checkStatus(httpResponse)
    }

    // MARK: - URL Builders

    /// Builds a URL for a thumbnail image, with the token as a query parameter
    /// so that image loaders can fetch it without setting custom headers.
    public func thumbURL(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url
    }

    /// Builds a URL for an audio stream, with the token as a query parameter
    /// so that Sonos speakers can fetch it without setting custom headers.
    public func audioURL(partKey: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = partKey
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url
    }

    // MARK: - Private Helpers

    /// Generic GET request that decodes a PlexResponse<T> and returns items.
    private func get<T: Codable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> [T] {
        let url = try buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request)
        request.timeoutInterval = 10

        let (data, httpResponse) = try await sendRequest(request)
        try checkStatus(httpResponse)

        let decoder = JSONDecoder()
        let response = try decoder.decode(PlexResponse<T>.self, from: data)
        return response.mediaContainer.items
    }

    /// Builds a URL from a path and optional query items.
    private func buildURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw PlexError.invalidURL("\(host):\(port)\(path)")
        }
        return url
    }

    /// Applies common Plex headers to a request.
    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// Sends the request, converting network errors to PlexError.serverUnreachable.
    private func sendRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await httpClient.send(request)
        } catch let error as PlexError {
            throw error
        } catch {
            throw PlexError.serverUnreachable
        }
    }

    /// Checks the HTTP status code and throws appropriate PlexError values.
    private func checkStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw PlexError.unauthorized
        default:
            throw PlexError.httpError(response.statusCode)
        }
    }
}
