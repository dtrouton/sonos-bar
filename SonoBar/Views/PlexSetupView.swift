// SonoBar/Views/PlexSetupView.swift
import SwiftUI
import SonoBarKit
#if canImport(Darwin)
import Darwin
#endif

struct PlexSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var serverIP = ""
    @State private var errorMessage: String?
    @State private var isScanning = false
    @State private var isAuthenticating = false
    @State private var authPinId: Int?
    @State private var discoveredServers: [String] = []

    private static let clientIdentifier = "com.sonobar.plex"
    private static let productName = "SonoBar"

    private var isConnected: Bool {
        appState.plexClient != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isConnected {
                    connectedView
                } else {
                    setupView
                }
            }
            .padding(16)
        }
    }

    // MARK: - Connected View

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                Text("Connected to Plex")
                    .font(.system(size: 13, weight: .semibold))
            }

            if let host = appState.plexClient?.host {
                Text("Server: \(host)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if !appState.plexLibraries.isEmpty {
                Text("Libraries: \(appState.plexLibraries.map(\.title).joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Button("Disconnect") {
                appState.disconnectPlex()
                serverIP = ""
                errorMessage = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Plex")
                .font(.system(size: 13, weight: .semibold))

            // Server IP
            VStack(alignment: .leading, spacing: 4) {
                Text("Server IP")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField("192.168.1.100", text: $serverIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button {
                        scanNetwork()
                    } label: {
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Text("Scan")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isScanning)
                }
            }

            // Discovered servers
            if !discoveredServers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found servers:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    ForEach(discoveredServers, id: \.self) { ip in
                        Button(ip) {
                            serverIP = ip
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    }
                }
            }

            // Error display
            if let errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            // Sign in button
            Button {
                Task { await signInWithPlex() }
            } label: {
                if isAuthenticating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for Plex sign-in...")
                    }
                } else {
                    Label("Sign in with Plex", systemImage: "person.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(serverIP.isEmpty || isAuthenticating)

            if isAuthenticating {
                Text("A browser window has opened. Sign in to your Plex account and click Allow.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Cancel") {
                    isAuthenticating = false
                    authPinId = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .onAppear {
            serverIP = UserDefaults.standard.string(forKey: "plexServerIP") ?? ""
            if serverIP.isEmpty {
                scanNetwork()
            }
        }
    }

    // MARK: - Plex OAuth PIN Flow

    private func signInWithPlex() async {
        errorMessage = nil
        isAuthenticating = true

        do {
            // Step 1: Request a PIN from plex.tv
            let pin = try await requestPin()
            authPinId = pin.id

            // Step 2: Open browser for user to authorize
            let authURL = "https://app.plex.tv/auth#?clientID=\(Self.clientIdentifier)&code=\(pin.code)&context%5Bdevice%5D%5Bproduct%5D=\(Self.productName)"
            if let url = URL(string: authURL) {
                NSWorkspace.shared.open(url)
            }

            // Step 3: Poll for the token (every 2 seconds, up to 2 minutes)
            let token = try await pollForToken(pinId: pin.id)

            // Step 4: Connect with the token
            let testClient = PlexClient(host: serverIP, token: token)
            let libraries = try await testClient.getLibraries()
            guard !libraries.isEmpty else {
                errorMessage = "Connected to Plex account but no libraries found on \(serverIP)."
                isAuthenticating = false
                return
            }

            appState.connectPlex(host: serverIP, token: token)
            isAuthenticating = false
        } catch PlexAuthError.cancelled {
            isAuthenticating = false
        } catch PlexAuthError.timeout {
            errorMessage = "Sign-in timed out. Please try again."
            isAuthenticating = false
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            isAuthenticating = false
        }
    }

    private struct PinResponse {
        let id: Int
        let code: String
    }

    private enum PlexAuthError: Error {
        case cancelled
        case timeout
        case invalidResponse
    }

    private func requestPin() async throws -> PinResponse {
        let url = URL(string: "https://plex.tv/api/v2/pins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(Self.productName, forHTTPHeaderField: "X-Plex-Product")
        request.httpBody = "strong=true".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)

        struct PinJSON: Codable {
            let id: Int
            let code: String
        }
        let pin = try JSONDecoder().decode(PinJSON.self, from: data)
        return PinResponse(id: pin.id, code: pin.code)
    }

    private func pollForToken(pinId: Int) async throws -> String {
        for _ in 0..<60 { // 2 minutes at 2-second intervals
            guard isAuthenticating else { throw PlexAuthError.cancelled }

            try await Task.sleep(for: .seconds(2))

            let url = URL(string: "https://plex.tv/api/v2/pins/\(pinId)")!
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(Self.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

            let (data, _) = try await URLSession.shared.data(for: request)

            struct TokenResponse: Codable {
                let authToken: String?
            }
            if let response = try? JSONDecoder().decode(TokenResponse.self, from: data),
               let token = response.authToken, !token.isEmpty {
                return token
            }
        }
        throw PlexAuthError.timeout
    }

    // MARK: - Network Scan

    private func scanNetwork() {
        isScanning = true
        discoveredServers = []
        Task {
            let found = await scanSubnetForPlex()
            discoveredServers = found
            if found.count == 1 {
                serverIP = found[0]
            }
            isScanning = false
        }
    }

    private func scanSubnetForPlex() async -> [String] {
        guard let localIP = getLocalIP() else { return [] }
        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let subnet = parts[0..<3].joined(separator: ".")

        return await withTaskGroup(of: String?.self) { group in
            for i in 1...254 {
                let ip = "\(subnet).\(i)"
                group.addTask {
                    let urlString = "http://\(ip):32400/identity"
                    guard let url = URL(string: urlString) else { return nil }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 0.3
                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                            return ip
                        }
                    } catch {}
                    return nil
                }
            }

            var results: [String] = []
            for await result in group {
                if let ip = result {
                    results.append(ip)
                }
            }
            return results.sorted()
        }
    }

    private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee
            guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: addr.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                         &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            return String(cString: hostname)
        }
        return nil
    }
}
