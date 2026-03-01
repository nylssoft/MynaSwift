import SwiftUI

struct LoginDialogView: View {
    @Binding var isPresented: Bool
    var onAuthenticated: ((AuthenticationResponse) -> Void)?
    private let authenticationService: AuthenticationServicing = RemoteAuthenticationService()

    @State private var username = ""
    @State private var password = ""
    @State private var secondFactorCode = ""
    @State private var isAwaitingSecondFactor = false
    @State private var pendingSecondFactorToken: String?
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Login")
                .font(.title2)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if isAwaitingSecondFactor {
                TextField("Second factor code", text: $secondFactorCode)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .disabled(isAuthenticating)

                if isAwaitingSecondFactor {
                    Button("Complete 2FA") {
                        Task {
                            await completeSecondFactor()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAuthenticating || secondFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Sign In") {
                        Task {
                            await signIn()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAuthenticating || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 8)

            if isAuthenticating {
                ProgressView(isAwaitingSecondFactor ? "Completing 2FA..." : "Signing in...")
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @MainActor
    private func signIn() async {
        isAuthenticating = true
        errorMessage = nil

        do {
            let request = try authenticationService.makeRequest(username: username, password: password)
            let response = try await authenticationService.authenticate(request)

            if response.requiresPass2 {
                guard let token = response.token,
                      !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AuthenticationError.twoFactorTokenMissing
                }
                pendingSecondFactorToken = token
                isAwaitingSecondFactor = true
                isAuthenticating = false
                return
            }

            AuthSessionStore.shared.save(from: response)
            onAuthenticated?(response)
            isPresented = false
        } catch {
            if let authenticationError = error as? AuthenticationError {
                errorMessage = authenticationError.errorDescription
            } else {
                errorMessage = "Unexpected authentication error."
            }
        }

        isAuthenticating = false
    }

    @MainActor
    private func completeSecondFactor() async {
        guard let pendingSecondFactorToken else {
            errorMessage = "No pending authentication request."
            return
        }

        isAuthenticating = true
        errorMessage = nil

        do {
            let response = try await authenticationService.completeSecondFactor(
                token: pendingSecondFactorToken,
                secondFactorCode: secondFactorCode
            )
            AuthSessionStore.shared.save(from: response)
            onAuthenticated?(response)
            isPresented = false
        } catch {
            if let authenticationError = error as? AuthenticationError {
                errorMessage = authenticationError.errorDescription
            } else {
                errorMessage = "Unexpected authentication error."
            }
        }

        isAuthenticating = false
    }
}
