// SSDPDiscovery.swift
// SonoBarKit
//
// Discovers Sonos speakers on the local network using SSDP (Simple Service Discovery Protocol).
// Sends M-SEARCH multicast messages and parses responses to identify Sonos ZonePlayers.

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - SSDPResult

/// Represents a discovered Sonos device from an SSDP response.
public struct SSDPResult: Sendable, Equatable {
    /// Full LOCATION URL from the SSDP response (e.g., http://192.168.1.42:1400/xml/device_description.xml)
    public let location: String
    /// Device UUID extracted from USN header (e.g., RINCON_48A6B88A7E4E01400)
    public let uuid: String
    /// IP address extracted from LOCATION URL
    public let ip: String
    /// Sonos household ID from X-RINCON-HOUSEHOLD header, if present
    public let householdID: String?

    public init(location: String, uuid: String, ip: String, householdID: String?) {
        self.location = location
        self.uuid = uuid
        self.ip = ip
        self.householdID = householdID
    }
}

// MARK: - SSDPResponseParser

/// Parses raw SSDP HTTP response strings into SSDPResult values.
/// Rejects non-Sonos devices by checking the SERVER header.
public enum SSDPResponseParser {

    /// Parses an SSDP response string and returns an SSDPResult if it's a valid Sonos device.
    /// Returns nil for non-Sonos devices or malformed responses.
    public static func parse(_ response: String) -> SSDPResult? {
        let headers = parseHeaders(response)

        // Reject non-Sonos devices
        guard let server = headers["SERVER"], server.contains("Sonos") else {
            return nil
        }

        // Require LOCATION header
        guard let location = headers["LOCATION"] else {
            return nil
        }

        // Extract IP from LOCATION URL
        guard let ip = extractIP(from: location) else {
            return nil
        }

        // Extract UUID from USN header
        guard let usn = headers["USN"], let uuid = extractUUID(from: usn) else {
            return nil
        }

        let householdID = headers["X-RINCON-HOUSEHOLD"]

        return SSDPResult(location: location, uuid: uuid, ip: ip, householdID: householdID)
    }

    // MARK: - Private helpers

    private static func parseHeaders(_ response: String) -> [String: String] {
        var headers: [String: String] = [:]
        let lines = response.components(separatedBy: "\r\n")
        for line in lines.dropFirst() { // Skip status line
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
            let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                headers[key] = value
            }
        }
        return headers
    }

    private static func extractIP(from location: String) -> String? {
        // Parse host from URL like http://192.168.1.42:1400/xml/...
        guard let url = URL(string: location), let host = url.host else {
            return nil
        }
        return host
    }

    private static func extractUUID(from usn: String) -> String? {
        // USN format: uuid:RINCON_48A6B88A7E4E01400::urn:...
        guard let uuidRange = usn.range(of: "uuid:") else { return nil }
        let afterUUID = usn[uuidRange.upperBound...]
        if let colonColonRange = afterUUID.range(of: "::") {
            return String(afterUUID[afterUUID.startIndex..<colonColonRange.lowerBound])
        }
        // If no :: suffix, take the rest
        return String(afterUUID)
    }
}

// MARK: - SSDPDiscovery

/// Performs SSDP multicast discovery to find Sonos speakers on the local network.
/// Uses BSD sockets (POSIX socket/sendto/recv) for UDP multicast.
public final class SSDPDiscovery: Sendable {

    /// The SSDP multicast address
    private static let multicastAddress = "239.255.255.250"
    /// The SSDP multicast port
    private static let multicastPort: UInt16 = 1900

    /// The M-SEARCH message sent to discover Sonos ZonePlayers.
    public static let mSearchMessage: String = {
        return "M-SEARCH * HTTP/1.1\r\n" +
               "HOST: 239.255.255.250:1900\r\n" +
               "MAN: \"ssdp:discover\"\r\n" +
               "MX: 1\r\n" +
               "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n" +
               "\r\n"
    }()

    public init() {}

    /// Scans the local network for Sonos speakers.
    /// - Parameter timeout: How long to listen for responses (in seconds). Default is 3.
    /// - Returns: Array of discovered Sonos devices, deduplicated by UUID.
    public func scan(timeout: TimeInterval = 3) async -> [SSDPResult] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let results = self.performScan(timeout: timeout)
                continuation.resume(returning: results)
            }
        }
    }

    // MARK: - Private BSD socket implementation

    private func performScan(timeout: TimeInterval) -> [SSDPResult] {
        // Create UDP socket
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [] }
        defer { close(sock) }

        // Allow address reuse
        var reuseAddr: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // Set receive timeout
        var tv = timeval()
        tv.tv_sec = Int(timeout)
        tv.tv_usec = Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Prepare multicast destination address
        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = SSDPDiscovery.multicastPort.bigEndian
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        inet_pton(AF_INET, SSDPDiscovery.multicastAddress, &destAddr.sin_addr)

        // Send M-SEARCH message
        let message = SSDPDiscovery.mSearchMessage
        let messageData = Array(message.utf8)
        let sent = withUnsafePointer(to: &destAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                sendto(sock, messageData, messageData.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard sent > 0 else { return [] }

        // Receive responses until timeout
        var seen = Set<String>()
        var results: [SSDPResult] = []
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let received = recv(sock, &buffer, buffer.count, 0)
            if received <= 0 { break } // Timeout or error

            if let response = String(bytes: buffer[0..<received], encoding: .utf8),
               let result = SSDPResponseParser.parse(response),
               !seen.contains(result.uuid) {
                seen.insert(result.uuid)
                results.append(result)
            }
        }

        return results
    }
}
