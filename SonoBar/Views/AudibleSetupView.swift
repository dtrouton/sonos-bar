// SonoBar/Views/AudibleSetupView.swift
import SwiftUI
import SonoBarKit

struct AudibleSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var errorMessage: String?
    @State private var isRegistering = false
    @State private var showPasteStep = false
    @State private var pastedURL = ""

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
                } else if showPasteStep {
                    pasteURLView
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

            if !appState.audibleBooks.isEmpty {
                Text("\(appState.audibleBooks.count) books in library")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Button("Disconnect") {
                appState.disconnectAudible()
                errorMessage = nil
                showPasteStep = false
                pastedURL = ""
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Setup View (Step 1: Open Browser)

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Audible")
                .font(.system(size: 13, weight: .semibold))

            Text("Sign in with your Amazon account in your browser to access your Audible library.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                startSignIn()
            } label: {
                Label("Sign in with Amazon", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Paste URL View (Step 2: Paste Redirect URL)

    private var pasteURLView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Complete Sign-in")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Label("A browser window has opened", systemImage: "1.circle.fill")
                    .font(.system(size: 11))
                Label("Sign in to your Amazon account", systemImage: "2.circle.fill")
                    .font(.system(size: 11))
                Label("After sign-in, copy the URL from the address bar", systemImage: "3.circle.fill")
                    .font(.system(size: 11))
                Label("Paste it below", systemImage: "4.circle.fill")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)

            Text("The page may show an error — that's expected. Just copy the full URL.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Paste URL here...", text: $pastedURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            if let errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("Cancel") {
                    showPasteStep = false
                    pastedURL = ""
                    errorMessage = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await handlePastedURL() }
                } label: {
                    if isRegistering {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Connecting...")
                        }
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(pastedURL.isEmpty || isRegistering)
            }
        }
    }

    // MARK: - Auth Flow

    private func startSignIn() {
        errorMessage = nil
        deviceSerial = AudibleAuth.generateDeviceSerial()
        clientId = AudibleAuth.buildClientId(serial: deviceSerial)
        codeVerifier = AudibleAuth.createCodeVerifier()

        let challenge = AudibleAuth.createCodeChallenge(verifier: codeVerifier)
        let authURL = AudibleAuth.buildAuthURL(clientId: clientId, codeChallenge: challenge)

        #if DEBUG
        print("[AudibleAuth] Auth URL: \(authURL.absoluteString)")
        #endif

        // Open in the user's default browser
        NSWorkspace.shared.open(authURL)
        showPasteStep = true
    }

    private func handlePastedURL() async {
        errorMessage = nil

        // Extract auth code from the pasted URL
        guard let url = URL(string: pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid URL. Please copy the full URL from your browser's address bar."
            return
        }

        guard let authCode = queryItems.first(where: { $0.name == "openid.oa2.authorization_code" })?.value,
              !authCode.isEmpty else {
            #if DEBUG
            print("[AudibleAuth] URL params: \(queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))")
            #endif
            errorMessage = "No authorization code found in URL. Make sure you completed the Amazon sign-in and copied the URL from the final page."
            return
        }

        await completeRegistration(authCode: authCode)
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

        #if DEBUG
        print("[AudibleAuth] Registration URL: \(request.url?.absoluteString ?? "nil")")
        print("[AudibleAuth] Auth code: \(authCode)")
        print("[AudibleAuth] Code verifier length: \(codeVerifier.count)")
        print("[AudibleAuth] Client ID: \(clientId)")
        print("[AudibleAuth] Device serial: \(deviceSerial)")
        if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            print("[AudibleAuth] Request body: \(bodyStr.prefix(800))")
        }
        #endif

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Registration failed: unexpected response"
                return
            }

            #if DEBUG
            print("[AudibleAuth] Registration HTTP \(httpResponse.statusCode)")
            if let body = String(data: data, encoding: .utf8) {
                print("[AudibleAuth] Response: \(body.prefix(500))")
            }
            #endif

            guard (200..<300).contains(httpResponse.statusCode) else {
                errorMessage = "Registration failed (HTTP \(httpResponse.statusCode))"
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
                errorMessage = "Registration failed: missing device credentials"
                return
            }

            let marketplace = String(AudibleAuth.domain.dropFirst("amazon.".count))

            appState.connectAudible(
                marketplace: marketplace,
                adpToken: adpToken,
                privateKeyPEM: devicePrivateKey,
                accessToken: accessToken,
                refreshToken: refreshToken,
                deviceSerial: deviceSerial
            )

            showPasteStep = false
            pastedURL = ""
        } catch {
            errorMessage = "Registration failed: \(error.localizedDescription)"
        }
    }
}
