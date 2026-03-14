// SonoBar/Views/PlexSetupView.swift
import SwiftUI
import SonoBarKit
#if canImport(Darwin)
import Darwin
#endif

struct PlexSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var serverIP = ""
    @State private var token = ""
    @State private var errorMessage: String?
    @State private var isConnecting = false
    @State private var isScanning = false
    @State private var discoveredServers: [String] = []

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
                token = ""
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

            // Token
            VStack(alignment: .leading, spacing: 4) {
                Text("Plex Token")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                SecureField("X-Plex-Token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text("Find your token at app.plex.tv/desktop > inspect network requests, or check Plex preferences XML.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            // Connect button
            Button {
                connect()
            } label: {
                if isConnecting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting...")
                    }
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(serverIP.isEmpty || token.isEmpty || isConnecting)
        }
    }

    // MARK: - Actions

    private func connect() {
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                let testClient = PlexClient(host: serverIP, token: token)
                let libraries = try await testClient.getLibraries()
                guard !libraries.isEmpty else {
                    errorMessage = "No libraries found. Check server IP and token."
                    isConnecting = false
                    return
                }
                appState.connectPlex(host: serverIP, token: token)
                isConnecting = false
            } catch let error as PlexError {
                switch error {
                case .unauthorized:
                    errorMessage = "Invalid token. Please check your Plex token."
                case .serverUnreachable:
                    errorMessage = "Cannot reach server at \(serverIP):32400."
                case .invalidURL(let url):
                    errorMessage = "Invalid URL: \(url)"
                case .httpError(let code):
                    errorMessage = "Server error (HTTP \(code))."
                }
                isConnecting = false
            } catch {
                errorMessage = "Connection failed: \(error.localizedDescription)"
                isConnecting = false
            }
        }
    }

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

    /// Scans the local subnet on port 32400 for Plex servers.
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
                    request.httpMethod = "GET"
                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                            return ip
                        }
                    } catch {
                        // Not a Plex server
                    }
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

    /// Gets the local IP from network interfaces (same approach as AppState).
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
