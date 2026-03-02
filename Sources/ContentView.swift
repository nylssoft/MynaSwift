import SwiftUI

struct ContentView: View {
    @State private var showLoginDialog = false
    @State private var showPinDialog = false
    @State private var isLoggedIn = false
    @State private var userInfo: UserInfoResponse?
    @State private var authentication: AuthenticationResponse?
    @State private var isCheckingStoredSession = false
    @State private var pendingLongLivedTokenForPin: String?

    private let authenticationService: AuthenticationServicing = RemoteAuthenticationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MynaSwift")
                .font(.largeTitle)
            Text("Sample macOS app with skeleton dialogs.")
                .foregroundStyle(.secondary)
            if isLoggedIn {
                HStack(spacing: 8) {
                    Text(userInfo.map { "Logged in as \($0.name)" } ?? "Logged in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Log out") {
                        AuthSessionStore.shared.clear()
                        self.isLoggedIn = false
                        self.authentication = nil
                        self.userInfo = nil
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else if isCheckingStoredSession {
                ProgressView("Validating saved session...")
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                Button(isLoggedIn ? "Switch User" : "Show Login Dialog") {
                    showLoginDialog = true
                }
                Button("Show About Dialog") {
                    AppDialogController.shared.showAboutDialog()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 260)
        .sheet(isPresented: $showLoginDialog) {
            LoginDialogView(isPresented: $showLoginDialog) { (authentication, userInfo) in
                isLoggedIn = true
                self.authentication = authentication
                self.userInfo = userInfo
            }
        }
        .sheet(isPresented: $showPinDialog) {
            PinDialogView(
                isPresented: $showPinDialog,
                onSubmit: { pin in
                    try await completePinAuthentication(pin: pin)
                },
                onCancel: {
                    pendingLongLivedTokenForPin = nil
                    AuthSessionStore.shared.clear()
                })
        }
        .task {
            await authenticateStoredSessionOnStartup()
        }
    }

    @MainActor
    private func authenticateStoredSessionOnStartup() async {
        guard !isLoggedIn else {
            return
        }
        guard let session = AuthSessionStore.shared.load() else {
            return
        }
        isCheckingStoredSession = true
        defer { isCheckingStoredSession = false }
        do {
            let authentication = try await authenticationService.authenticateLongLivedToken(
                longLivedToken: session.longLivedToken)
            if authentication.requiresPin {
                pendingLongLivedTokenForPin = session.longLivedToken
                showPinDialog = true
                return
            }
            guard let token = authentication.token
            else {
                AuthSessionStore.shared.clear()
                return
            }
            let userInfo = try await authenticationService.getUserInfo(token: token)
            self.authentication = authentication
            self.userInfo = userInfo
            self.isLoggedIn = true
            AuthSessionStore.shared.save(from: authentication)
        } catch {
            AuthSessionStore.shared.clear()
        }
    }

    @MainActor
    private func completePinAuthentication(pin: String) async throws {
        guard let token = pendingLongLivedTokenForPin
        else {
            throw AuthenticationError.twoFactorTokenMissing
        }
        let authentication = try await authenticationService.completePin(
            longLivedToken: token, pin: pin)
        guard let token = authentication.token
        else {
            throw AuthenticationError.serverError(
                "PIN authentication did not return an access token.")
        }
        let userInfo = try await authenticationService.getUserInfo(token: token)
        self.authentication = authentication
        self.userInfo = userInfo
        self.isLoggedIn = true
        pendingLongLivedTokenForPin = nil
        AuthSessionStore.shared.save(from: authentication)
    }
}
