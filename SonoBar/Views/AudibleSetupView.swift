// SonoBar/Views/AudibleSetupView.swift
import SwiftUI
import WebKit
import SonoBarKit

struct AudibleSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var errorMessage: String?
    @State private var isRegistering = false
    @State private var showWebView = false

    // Auth flow state
    @State private var deviceSerial = ""
    @State private var clientId = ""
    @State private var codeVerifier = ""

    private var isConnected: Bool {
        appState.audibleClient != nil
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
                Text("Connected to Audible")
                    .font(.system(size: 13, weight: .semibold))
            }

            if let client = appState.audibleClient {
                Text("Marketplace: \(client.marketplace)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if !appState.audibleBooks.isEmpty {
                Text("\(appState.audibleBooks.count) books in library")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Button("Disconnect") {
                appState.disconnectAudible()
                errorMessage = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Audible")
                .font(.system(size: 13, weight: .semibold))

            Text("Sign in with your Amazon account to access your Audible library.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                startSignIn()
            } label: {
                if isRegistering {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Registering device...")
                    }
                } else {
                    Label("Sign in with Amazon", systemImage: "person.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isRegistering)
            .sheet(isPresented: $showWebView) {
                webViewSheet
            }
        }
    }

    // MARK: - WebView Sheet

    private var webViewSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Amazon")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    showWebView = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            let authURL = AudibleAuth.buildAuthURL(
                clientId: clientId,
                codeChallenge: AudibleAuth.createCodeChallenge(verifier: codeVerifier)
            )
            AmazonWebView(url: authURL) { authCode in
                showWebView = false
                Task { await completeRegistration(authCode: authCode) }
            }
        }
        .frame(width: 440, height: 600)
    }

    // MARK: - Auth Flow

    private func startSignIn() {
        errorMessage = nil
        deviceSerial = AudibleAuth.generateDeviceSerial()
        clientId = AudibleAuth.buildClientId(serial: deviceSerial)
        codeVerifier = AudibleAuth.createCodeVerifier()
        #if DEBUG
        let challenge = AudibleAuth.createCodeChallenge(verifier: codeVerifier)
        let url = AudibleAuth.buildAuthURL(clientId: clientId, codeChallenge: challenge)
        print("[AudibleAuth] Auth URL: \(url.absoluteString)")
        #endif
        showWebView = true
    }

    private func completeRegistration(authCode: String) async {
        isRegistering = true
        defer { isRegistering = false }

        let request = AudibleAuth.buildRegistrationRequest(
            authCode: authCode,
            codeVerifier: codeVerifier,
            clientId: clientId,
            deviceSerial: deviceSerial
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                errorMessage = "Registration failed (HTTP \(statusCode))"
                return
            }

            // Parse the nested response JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseObj = json["response"] as? [String: Any],
                  let success = responseObj["success"] as? [String: Any],
                  let tokens = success["tokens"] as? [String: Any] else {
                errorMessage = "Registration failed: unexpected response format"
                return
            }

            guard let bearer = tokens["bearer"] as? [String: Any],
                  let accessToken = bearer["access_token"] as? String,
                  let refreshToken = bearer["refresh_token"] as? String else {
                errorMessage = "Registration failed: missing bearer tokens"
                return
            }

            guard let macDms = tokens["mac_dms"] as? [String: Any],
                  let adpToken = macDms["adp_token"] as? String,
                  let devicePrivateKey = macDms["device_private_key"] as? String else {
                errorMessage = "Registration failed: missing MAC DMS tokens"
                return
            }

            // Store everything and connect
            AudibleKeychain.setAccessToken(accessToken)
            AudibleKeychain.setRefreshToken(refreshToken)
            AudibleKeychain.setAdpToken(adpToken)
            AudibleKeychain.setPrivateKeyPEM(devicePrivateKey)
            AudibleKeychain.setDeviceSerial(deviceSerial)

            // Derive marketplace from the auth domain (e.g. "co.uk" from "amazon.co.uk")
            let marketplace = String(AudibleAuth.domain.dropFirst("amazon.".count))

            appState.connectAudible(
                marketplace: marketplace,
                adpToken: adpToken,
                privateKeyPEM: devicePrivateKey,
                accessToken: accessToken,
                refreshToken: refreshToken,
                deviceSerial: deviceSerial
            )
        } catch {
            errorMessage = "Registration failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - AmazonWebView (WKWebView Wrapper)

struct AmazonWebView: NSViewRepresentable {
    let url: URL
    var onAuthCode: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use a non-persistent data store so Amazon can't reuse cached sessions
        // — forces full login flow with OAuth extension processing
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthCode: onAuthCode)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onAuthCode: (String) -> Void

        init(onAuthCode: @escaping (String) -> Void) {
            self.onAuthCode = onAuthCode
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            #if DEBUG
            print("[AudibleAuth] Navigation to: \(url.absoluteString.prefix(200))")
            #endif

            guard url.absoluteString.contains("maplanding") else {
                decisionHandler(.allow)
                return
            }

            #if DEBUG
            print("[AudibleAuth] Maplanding detected! Full URL: \(url.absoluteString)")
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                for item in components.queryItems ?? [] {
                    print("[AudibleAuth]   \(item.name) = \(item.value ?? "nil")")
                }
            }
            #endif

            // Extract authorization code from query params
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let authCode = queryItems.first(where: { $0.name == "openid.oa2.authorization_code" })?.value,
               !authCode.isEmpty {
                decisionHandler(.cancel)
                onAuthCode(authCode)
            } else {
                // Maplanding without auth code — likely an error from Amazon
                #if DEBUG
                print("[AudibleAuth] Maplanding but no authorization_code found")
                #endif
                decisionHandler(.allow)
            }
        }
    }
}
