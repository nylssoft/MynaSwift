import Foundation
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
                HStack(alignment: .top, spacing: 12) {
                    if let profileImageURL = profileImageURL {
                        AsyncImage(url: profileImageURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline)

                        if let email = userInfo?.email, !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let lastLoginText {
                            Text("Last login: \(lastLoginText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let registeredText {
                            Text("Registered: \(registeredText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Log out") {
                            AuthSessionStore.shared.clear()
                            self.isLoggedIn = false
                            self.authentication = nil
                            self.userInfo = nil
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            } else if isCheckingStoredSession {
                ProgressView("Validating saved session...")
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                Button(isLoggedIn ? "Switch User" : "Login") {
                    showLoginDialog = true
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 260)
        .sheet(isPresented: $showLoginDialog) {
            LoginDialogView(
                isPresented: $showLoginDialog,
                onAuthenticated: { (authentication, userInfo) in
                    isLoggedIn = true
                    self.authentication = authentication
                    self.userInfo = userInfo
                })
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
                    presentStartupLoginDialog()
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
            presentStartupLoginDialog()
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
                presentStartupLoginDialog()
                return
            }
            let userInfo = try await authenticationService.getUserInfo(token: token)
            self.authentication = authentication
            self.userInfo = userInfo
            self.isLoggedIn = true
            AuthSessionStore.shared.save(from: authentication)
        } catch {
            AuthSessionStore.shared.clear()
            presentStartupLoginDialog()
        }
    }

    @MainActor
    private func presentStartupLoginDialog() {
        showLoginDialog = true
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

    private var displayName: String {
        guard let name = userInfo?.name, !name.isEmpty else {
            return "Logged in"
        }
        return name
    }

    private var profileImageURL: URL? {
        guard let photo = userInfo?.photo,
            !photo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return URL(string: photo, relativeTo: URL(string: "https://www.stockfleth.eu"))
    }

    private var lastLoginText: String? {
        guard let lastLoginUtc = userInfo?.lastLoginUtc,
            let date = parseUTCISODate(lastLoginUtc)
        else {
            return nil
        }
        return displayDateFormatter.string(from: date)
    }

    private var registeredText: String? {
        guard let registeredUtc = userInfo?.registeredUtc,
            let date = parseUTCISODate(registeredUtc)
        else {
            return nil
        }
        return displayDateFormatter.string(from: date)
    }

    private var displayDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func parseUTCISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
