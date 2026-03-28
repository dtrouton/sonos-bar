// AudibleClient.swift
// SonoBarKit
//
// HTTP client for communicating with the Audible API.
// Uses the same HTTPClientProtocol as SOAPClient for testability.

import Foundation

// MARK: - AudibleError

public enum AudibleError: Error, Sendable, Equatable {
    case invalidURL(String)
    case unauthorized
    case httpError(Int)
    case serverUnreachable
}

// MARK: - AudibleClient

public final class AudibleClient: Sendable {
    public let marketplace: String  // e.g. "co.uk"
    private let adpToken: String
    private let privateKeyPEM: String
    private let accessToken: String
    private let httpClient: HTTPClientProtocol

    public init(
        marketplace: String,
        adpToken: String,
        privateKeyPEM: String,
        accessToken: String,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.marketplace = marketplace
        self.adpToken = adpToken
        self.privateKeyPEM = privateKeyPEM
        self.accessToken = accessToken
        self.httpClient = httpClient
    }

    // MARK: - Library

    /// Fetches the user's Audible library sorted by most recent purchase.
    /// GET /1.0/library?num_results=500&response_groups=product_attrs,media,product_desc&sort_by=-PurchaseDate
    public func getLibrary() async throws -> [AudibleBook] {
        let data = try await get("/1.0/library", queryItems: [
            URLQueryItem(name: "num_results", value: "500"),
            URLQueryItem(name: "response_groups", value: "product_attrs,media,product_desc"),
            URLQueryItem(name: "sort_by", value: "-PurchaseDate"),
        ])

        let response = try JSONDecoder().decode(LibraryResponse.self, from: data)
        return response.items
    }

    // MARK: - Chapters

    /// Fetches chapter info for a specific audiobook.
    /// GET /1.0/library/{asin}?response_groups=chapter_info
    public func getChapters(asin: String) async throws -> [AudibleChapter] {
        let data = try await get("/1.0/library/\(asin)", queryItems: [
            URLQueryItem(name: "response_groups", value: "chapter_info"),
        ])

        let response = try JSONDecoder().decode(AudibleChapterResponse.self, from: data)
        return response.chapters
    }

    // MARK: - Listening Positions

    /// Fetches last listening positions for the given ASINs.
    /// GET /1.0/annotations/lastpositions?asins={asin1,asin2,...}
    public func getListeningPositions(asins: [String]) async throws -> [AudibleListeningPosition] {
        let data = try await get("/1.0/annotations/lastpositions", queryItems: [
            URLQueryItem(name: "asins", value: asins.joined(separator: ",")),
        ])

        let response = try JSONDecoder().decode(AudibleListeningPositionResponse.self, from: data)
        return response.items
    }

    // MARK: - Cover URL

    /// Constructs a cover image URL from the path returned by the API.
    public func coverURL(path: String) -> URL? {
        URL(string: path)
    }

    // MARK: - Private Helpers

    /// Library response wrapper.
    private struct LibraryResponse: Codable {
        let items: [AudibleBook]
    }

    /// Generic GET request that builds URL, signs the request, and returns raw data.
    private func get(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let url = try buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request)
        request.timeoutInterval = 10

        try AudibleAuth.signRequest(&request, adpToken: adpToken, privateKeyPEM: privateKeyPEM)

        let (data, httpResponse) = try await sendRequest(request)
        try checkStatus(httpResponse)
        return data
    }

    /// Builds a URL for the Audible API.
    private func buildURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.audible.\(marketplace)"
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw AudibleError.invalidURL("api.audible.\(marketplace)\(path)")
        }
        return url
    }

    /// Applies common headers to a request.
    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// Sends the request, converting network errors to AudibleError.serverUnreachable.
    private func sendRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await httpClient.send(request)
        } catch let error as AudibleError {
            throw error
        } catch {
            throw AudibleError.serverUnreachable
        }
    }

    /// Checks the HTTP status code and throws appropriate AudibleError values.
    private func checkStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw AudibleError.unauthorized
        default:
            throw AudibleError.httpError(response.statusCode)
        }
    }
}
