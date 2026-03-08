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

    private let registrationURL = URL(string: "https://www.stockfleth.eu")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.s("login.title"))
                .font(.title2)

            TextField(L10n.s("login.username"), text: $username)
                .textFieldStyle(.roundedBorder)
                .disabled(isAwaitingSecondFactor)
                .focused($focusedField, equals: .username)

            SecureField(L10n.s("login.password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .disabled(isAwaitingSecondFactor)
                .focused($focusedField, equals: .password)

            Toggle(L10n.s("login.keepSignedIn"), isOn: $keepLogin)
                .disabled(isAuthenticating)
                .onChange(of: keepLogin) { _, newValue in
                    AuthSessionStore.shared.setKeepLoginEnabled(newValue)
                }

            if !isAwaitingSecondFactor,
                let registrationURL
            {
                Link(L10n.s("login.registerIfNoAccount"), destination: registrationURL)
                    .font(.caption)
            }

            if isAwaitingSecondFactor {
                TextField(L10n.s("login.secondFactorCode"), text: $secondFactorCode)
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

                Button(L10n.s("common.cancel")) {
                    isPresented = false
                }
                .disabled(isAuthenticating)

                if isAwaitingSecondFactor {
                    Button(L10n.s("login.complete2fa")) {
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
                    Button(L10n.s("login.signIn")) {
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
                ProgressView(
                    isAwaitingSecondFactor
                        ? L10n.s("login.progress.completing2fa")
                        : L10n.s("login.progress.signingIn")
                )
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 420)
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
                errorMessage = L10n.s("error.authentication.unexpected")
            }
        }
        isAuthenticating = false
    }

    @MainActor
    private func completeSecondFactor() async {
        guard let pendingSecondFactorToken else {
            errorMessage = L10n.s("error.authentication.noPendingRequest")
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
                errorMessage = L10n.s("error.authentication.unexpected")
            }
        }
        isAuthenticating = false
    }
}
