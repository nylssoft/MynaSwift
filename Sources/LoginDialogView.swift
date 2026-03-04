import SwiftUI

struct LoginDialogView: View {
    private enum Field {
        case username
        case password
        case secondFactor
    }

    @Binding var isPresented: Bool
    var onAuthenticated: ((AuthenticationResponse, UserInfoResponse) -> Void)?
    private let service: Servicing = RemoteService()

    @State private var username = ""
    @State private var password = ""
    @State private var secondFactorCode = ""
    @State private var isAwaitingSecondFactor = false
    @State private var pendingSecondFactorToken: String?
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var keepLogin = AuthSessionStore.shared.keepLoginEnabled
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Login")
                .font(.title2)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .disabled(isAwaitingSecondFactor)
                .focused($focusedField, equals: .username)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .disabled(isAwaitingSecondFactor)
                .focused($focusedField, equals: .password)

            Toggle("Keep me signed in", isOn: $keepLogin)
                .disabled(isAuthenticating)
                .onChange(of: keepLogin) { _, newValue in
                    AuthSessionStore.shared.setKeepLoginEnabled(newValue)
                }

            if isAwaitingSecondFactor {
                TextField("Second factor code", text: $secondFactorCode)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .secondFactor)
                    .onAppear {
                        DispatchQueue.main.async {
                            focusedField = .secondFactor
                        }
                    }
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
                    .disabled(
                        isAuthenticating
                            || secondFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                    )
                } else {
                    Button("Sign In") {
                        Task {
                            await signIn()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isAuthenticating
                            || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .onChange(of: isAwaitingSecondFactor) { _, newValue in
            if newValue {
                DispatchQueue.main.async {
                    focusedField = .secondFactor
                }
            } else {
                focusedField = .username
            }
        }
        .onAppear {
            focusedField = .username
        }
    }

    @MainActor
    private func signIn() async {
        isAuthenticating = true
        errorMessage = nil
        do {
            let authentication = try await service.authenticate(
                username: username, password: password)
            if authentication.requiresPass2 {
                guard let token = authentication.token,
                    !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw ServiceError.twoFactorTokenMissing
                }
                pendingSecondFactorToken = token
                isAwaitingSecondFactor = true
                isAuthenticating = false
                return
            }
            let userInfo = try await service.getUserInfo(token: authentication.token!)
            AuthSessionStore.shared.persistSession(from: authentication, keepLogin: keepLogin)
            onAuthenticated?(authentication, userInfo)
            isPresented = false
        } catch {
            if let authenticationError = error as? ServiceError {
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
            let authentication = try await service.completeSecondFactor(
                token: pendingSecondFactorToken,
                secondFactorCode: secondFactorCode
            )
            let userInfo = try await service.getUserInfo(token: authentication.token!)
            AuthSessionStore.shared.persistSession(from: authentication, keepLogin: keepLogin)
            onAuthenticated?(authentication, userInfo)
            isPresented = false
        } catch {
            if let authenticationError = error as? ServiceError {
                errorMessage = authenticationError.errorDescription
            } else {
                errorMessage = "Unexpected authentication error."
            }
        }
        isAuthenticating = false
    }
}
