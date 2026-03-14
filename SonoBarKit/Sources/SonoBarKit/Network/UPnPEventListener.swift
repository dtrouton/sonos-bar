// UPnPEventListener.swift
// SonoBarKit
//
// Handles UPnP event subscriptions and provides a lightweight HTTP server
// to receive event notifications from Sonos speakers via NWListener.

import Foundation
import Network

// MARK: - UPnPSubscription

/// Builds HTTP requests for UPnP event subscription management.
public enum UPnPSubscription {

    /// Default subscription timeout in seconds.
    public static let defaultTimeout: Int = 3600

    /// Builds a SUBSCRIBE request to initiate a new event subscription.
    ///
    /// - Parameters:
    ///   - speakerHost: IP address of the Sonos speaker
    ///   - service: The UPnP service to subscribe to
    ///   - callbackURL: Full URL the speaker should POST events to
    ///   - timeout: Subscription duration in seconds (default 3600)
    /// - Returns: A configured URLRequest
    public static func buildSubscribeRequest(
        speakerHost: String,
        service: SonosService,
        callbackURL: String,
        timeout: Int = defaultTimeout
    ) -> URLRequest {
        let url = eventURL(speakerHost: speakerHost, service: service)
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.setValue("<\(callbackURL)>", forHTTPHeaderField: "CALLBACK")
        request.setValue("upnp:event", forHTTPHeaderField: "NT")
        request.setValue("Second-\(timeout)", forHTTPHeaderField: "TIMEOUT")
        return request
    }

    /// Builds a SUBSCRIBE request to renew an existing subscription.
    ///
    /// - Parameters:
    ///   - speakerHost: IP address of the Sonos speaker
    ///   - service: The UPnP service to renew subscription for
    ///   - sid: The subscription ID to renew
    ///   - timeout: New subscription duration in seconds (default 3600)
    /// - Returns: A configured URLRequest
    public static func buildRenewRequest(
        speakerHost: String,
        service: SonosService,
        sid: String,
        timeout: Int = defaultTimeout
    ) -> URLRequest {
        let url = eventURL(speakerHost: speakerHost, service: service)
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.setValue(sid, forHTTPHeaderField: "SID")
        request.setValue("Second-\(timeout)", forHTTPHeaderField: "TIMEOUT")
        return request
    }

    /// Builds an UNSUBSCRIBE request to cancel an event subscription.
    ///
    /// - Parameters:
    ///   - speakerHost: IP address of the Sonos speaker
    ///   - service: The UPnP service to unsubscribe from
    ///   - sid: The subscription ID to cancel
    /// - Returns: A configured URLRequest
    public static func buildUnsubscribeRequest(
        speakerHost: String,
        service: SonosService,
        sid: String
    ) -> URLRequest {
        let url = eventURL(speakerHost: speakerHost, service: service)
        var request = URLRequest(url: url)
        request.httpMethod = "UNSUBSCRIBE"
        request.setValue(sid, forHTTPHeaderField: "SID")
        return request
    }

    // MARK: - Private

    private static func eventURL(speakerHost: String, service: SonosService) -> URL {
        // Force-unwrap is safe here because we control the URL format
        return URL(string: "http://\(speakerHost):1400\(service.eventURL)")!
    }
}

// MARK: - EventCallback

/// Closure type for receiving parsed UPnP event notifications.
/// Parameters: the service that generated the event, and a dictionary of changed properties.
public typealias EventCallback = @Sendable (SonosService, [String: String]) -> Void

// MARK: - UPnPEventListener

/// A lightweight HTTP server that listens for UPnP event NOTIFY messages from Sonos speakers.
/// Uses NWListener from the Network framework to accept TCP connections on a random port.
public final class UPnPEventListener: @unchecked Sendable {

    /// The TCP port the listener is running on, or nil if not started.
    public var port: UInt16? {
        lock.withLock { _port }
    }

    private var _port: UInt16?
    private var _listener: NWListener?
    private var _onEvent: EventCallback?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.sonobar.eventlistener", qos: .userInitiated)

    public init() {}

    // MARK: - Public API

    /// Returns the callback URL path for a given service.
    /// Format: `/event/{service.rawValue}`
    public static func callbackPath(for service: SonosService) -> String {
        return "/event/\(service.rawValue)"
    }

    /// Starts the HTTP listener on a random available port.
    /// Tries up to 5 ports if initial attempts fail.
    ///
    /// - Parameter onEvent: Closure called when an event notification is received.
    /// - Throws: If no port could be bound after 5 attempts.
    public func start(onEvent: @escaping EventCallback) async throws {
        lock.withLock { self._onEvent = onEvent }

        var lastError: Error?
        for _ in 0..<5 {
            do {
                try await startListener()
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SOAPError(code: -1, message: "Failed to start event listener")
    }

    /// Stops the HTTP listener and cancels all connections.
    public func stop() {
        let currentListener = lock.withLock { () -> NWListener? in
            let l = _listener
            _listener = nil
            _port = nil
            _onEvent = nil
            return l
        }
        currentListener?.cancel()
    }

    // MARK: - Private

    /// Thread-safe box for tracking whether a continuation has been resumed.
    private final class ResumeGuard: @unchecked Sendable {
        private var _resumed = false
        private let lock = NSLock()

        var resumed: Bool {
            lock.withLock { _resumed }
        }

        /// Attempts to mark as resumed. Returns true if this was the first call.
        func tryResume() -> Bool {
            lock.withLock {
                if _resumed { return false }
                _resumed = true
                return true
            }
        }
    }

    private func startListener() async throws {
        let params = NWParameters.tcp
        let nwListener = try NWListener(using: params)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let guard_ = ResumeGuard()

            nwListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if guard_.tryResume() {
                        if let self, let nwPort = nwListener.port {
                            self.lock.withLock { self._port = nwPort.rawValue }
                        }
                        continuation.resume()
                    }
                case .failed(let error):
                    if guard_.tryResume() {
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    if guard_.tryResume() {
                        continuation.resume(throwing: SOAPError(code: -1, message: "Listener cancelled"))
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            self.lock.withLock { self._listener = nwListener }
            nwListener.start(queue: self.queue)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        // Receive the full HTTP request (up to 64KB should be plenty for UPnP events)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            defer {
                // Send HTTP 200 OK response
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                let responseData = Data(response.utf8)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }

            guard let self = self,
                  let data = data,
                  let rawRequest = String(data: data, encoding: .utf8) else {
                return
            }

            self.processHTTPRequest(rawRequest)
        }
    }

    private func processHTTPRequest(_ rawRequest: String) {
        // Split headers and body
        guard let headerBodySplit = rawRequest.range(of: "\r\n\r\n") else { return }
        let headerSection = String(rawRequest[rawRequest.startIndex..<headerBodySplit.lowerBound])
        let body = String(rawRequest[headerBodySplit.upperBound...])

        // Extract path from request line (e.g., "NOTIFY /event/avTransport HTTP/1.1")
        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        let path = parts[1]

        // Match path to a service
        guard let service = serviceFromPath(path) else { return }

        // Parse the event XML body
        guard !body.isEmpty else { return }
        if let properties = try? XMLResponseParser.parseEventBody(body) {
            let callback = lock.withLock { _onEvent }
            callback?(service, properties)
        }
    }

    private func serviceFromPath(_ path: String) -> SonosService? {
        for service in SonosService.allCases {
            if path == UPnPEventListener.callbackPath(for: service) {
                return service
            }
        }
        return nil
    }
}
