import SwiftUI

struct ContentView: View {
    @State private var showLoginDialog = false
    @State private var isLoggedIn = false
    @State private var userInfo: UserInfoResponse?
    @State private var authentication: AuthenticationResponse?
    @State private var isCheckingStoredSession = false

    private let authenticationService: AuthenticationServicing = RemoteAuthenticationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MynaSwift")
                .font(.largeTitle)
            Text("Sample macOS app with skeleton dialogs.")
                .foregroundStyle(.secondary)
            if isLoggedIn {
                HStack(spacing: 8) {
                    Text(userInfo.map { "Logged in as \($0.name!)" } ?? "Logged in")
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
            let isValid = true // try await authenticationService.validateStoredSession(session)
            if isValid {
                // TODO authenticate with longLivedToken
            } else {
            }
        } catch {
            AuthSessionStore.shared.clear()
        }
    }
}
