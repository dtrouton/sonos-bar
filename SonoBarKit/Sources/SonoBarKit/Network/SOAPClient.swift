// SOAPClient.swift
// SonoBarKit
//
// HTTP transport layer for sending SOAP requests to Sonos devices
// and parsing their responses.

import Foundation

// MARK: - URLRequestSnapshot

/// A simple value-type snapshot of a URLRequest for test inspection
/// without requiring Foundation import in test files.
public struct URLRequestSnapshot: Sendable {
    public let urlString: String
    public let method: String
    public let contentType: String?
    public let soapAction: String?
    public let timeout: TimeInterval
    public let bodyString: String?

    public init(_ request: URLRequest) {
        self.urlString = request.url?.absoluteString ?? ""
        self.method = request.httpMethod ?? "GET"
        self.contentType = request.value(forHTTPHeaderField: "Content-Type")
        self.soapAction = request.value(forHTTPHeaderField: "SOAPACTION")
        self.timeout = request.timeoutInterval
        if let body = request.httpBody {
            self.bodyString = String(data: body, encoding: .utf8)
        } else {
            self.bodyString = nil
        }
    }
}

// MARK: - HTTPClientProtocol

/// Abstraction over HTTP transport for testability.
public protocol HTTPClientProtocol: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// MARK: - URLSessionHTTPClient

/// Default HTTP client implementation backed by URLSession.shared.
public struct URLSessionHTTPClient: HTTPClientProtocol {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SOAPError(code: -1, message: "Response is not an HTTP response")
        }
        return (data, httpResponse)
    }
}

// MARK: - SOAPClient

/// Sends SOAP actions to a Sonos speaker and returns parsed response dictionaries.
public final class SOAPClient: Sendable {
    public let host: String
    public let port: Int
    private let httpClient: HTTPClientProtocol

    public init(host: String, port: Int = 1400, httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.host = host
        self.port = port
        self.httpClient = httpClient
    }

    // MARK: - Dictionary overload

    /// Sends a SOAP action with dictionary params (keys sorted alphabetically).
    public func callAction(
        service: SonosService,
        action: String,
        params: [String: String]
    ) async throws -> [String: String] {
        let body = SOAPEnvelope.build(service: service, action: action, params: params)
        return try await sendRequest(service: service, action: action, body: body)
    }

    // MARK: - Tuple overload

    /// Sends a SOAP action with ordered tuple params (preserves parameter order).
    public func callAction(
        service: SonosService,
        action: String,
        params: [(String, String)]
    ) async throws -> [String: String] {
        let body = SOAPEnvelope.build(service: service, action: action, params: params)
        return try await sendRequest(service: service, action: action, body: body)
    }

    // MARK: - Private

    /// Core request builder and sender shared by both overloads.
    private func sendRequest(
        service: SonosService,
        action: String,
        body: String
    ) async throws -> [String: String] {
        let urlString = "http://\(host):\(port)\(service.controlURL)"
        guard let url = URL(string: urlString) else {
            throw SOAPError(code: -1, message: "Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(
            SOAPEnvelope.soapActionHeader(service: service, action: action),
            forHTTPHeaderField: "SOAPACTION"
        )
        request.timeoutInterval = 5
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await httpClient.send(request)
        let responseXML = String(data: data, encoding: .utf8) ?? ""
        return try XMLResponseParser.parse(responseXML)
    }
}
