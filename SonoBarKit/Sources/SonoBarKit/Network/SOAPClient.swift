// SOAPClient.swift
// SonoBarKit
//
// HTTP transport layer for sending SOAP requests to Sonos devices
// and parsing their responses.

import Foundation

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

        let (data, httpResponse) = try await httpClient.send(request)
        let responseXML = String(data: data, encoding: .utf8) ?? ""

        // Parse XML first — SOAP faults come as 500 with a fault envelope
        let parsed = try XMLResponseParser.parse(responseXML)

        // If parsing succeeded but HTTP status is non-2xx and non-500
        // (500 is handled by XMLResponseParser via SOAP faults)
        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300,
           httpResponse.statusCode != 500 {
            throw SOAPError(code: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
        }

        return parsed
    }
}
