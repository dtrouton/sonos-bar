// GroupManager.swift
// SonoBarKit
//
// Manages Sonos speaker grouping (joining/leaving groups) via SOAP commands.

/// Manages Sonos multi-room speaker grouping operations.
public enum GroupManager {

    /// Joins a member speaker to a coordinator's group by setting its transport URI.
    /// - Parameters:
    ///   - memberClient: SOAPClient for the member speaker to be joined.
    ///   - coordinatorUUID: UUID of the group coordinator (e.g., "RINCON_AAA").
    public static func joinToCoordinator(
        memberClient: SOAPClient,
        coordinatorUUID: String
    ) async throws {
        _ = try await memberClient.callAction(
            service: .avTransport,
            action: "SetAVTransportURI",
            params: [
                ("InstanceID", "0"),
                ("CurrentURI", "x-rincon:\(coordinatorUUID)"),
                ("CurrentURIMetaData", "")
            ]
        )
    }

    /// Groups multiple speakers under a coordinator using concurrent tasks.
    /// - Parameters:
    ///   - memberIPs: IP addresses of speakers to join to the group.
    ///   - coordinatorUUID: UUID of the group coordinator.
    ///   - httpClient: Optional HTTP client for testability (defaults to URLSessionHTTPClient).
    public static func group(
        memberIPs: [String],
        coordinatorUUID: String,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for ip in memberIPs {
                taskGroup.addTask {
                    let client = SOAPClient(host: ip, httpClient: httpClient)
                    try await joinToCoordinator(
                        memberClient: client,
                        coordinatorUUID: coordinatorUUID
                    )
                }
            }
            // Wait for all tasks to complete, propagating any errors
            try await taskGroup.waitForAll()
        }
    }

    /// Removes a speaker from its current group, making it a standalone coordinator.
    /// - Parameter client: SOAPClient for the speaker to ungroup.
    public static func ungroup(client: SOAPClient) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "BecomeCoordinatorOfStandaloneGroup",
            params: [("InstanceID", "0")]
        )
    }
}
