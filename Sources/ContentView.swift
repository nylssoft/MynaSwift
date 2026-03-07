import Foundation
import SwiftUI

struct ContentView: View {
    private enum WorkspaceSection: String, CaseIterable, Identifiable {
        case notes
        case documents
        case passwords
        case contacts
        case appointments
        case diaryEntries

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes:
                return L10n.s("section.notes")
            case .documents:
                return L10n.s("section.documents")
            case .passwords:
                return L10n.s("section.passwords")
            case .contacts:
                return L10n.s("section.contacts")
            case .appointments:
                return L10n.s("section.appointments")
            case .diaryEntries:
                return L10n.s("section.diaryEntries")
            }
        }

        var iconName: String {
            switch self {
            case .notes:
                return "note.text"
            case .documents:
                return "doc.text"
            case .passwords:
                return "key"
            case .contacts:
                return "person.2"
            case .appointments:
                return "calendar"
            case .diaryEntries:
                return "book.closed"
            }
        }
    }

    @State private var showLoginDialog = false
    @State private var showPinDialog = false
    @State private var isLoggedIn = false
    @State private var userInfo: UserInfoResponse?
    @State private var authentication: AuthenticationResponse?
    @State private var isCheckingStoredSession = false
    @State private var pendingLongLivedTokenForPin: String?
    @AppStorage("contentView.selectedSection") private var selectedSectionRawValue =
        WorkspaceSection.notes.rawValue
    @State private var showDataProtectionDialog = false
    @State private var dataProtectionSecurityKey = ""
    @State private var isLoggingOut = false
    @State private var activityStatusMessage: String?
    @State private var statusBarMessage: String?
    @State private var clearStatusBarTask: Task<Void, Never>?
    @AppStorage("contentView.isUserDetailsCollapsed") private var isUserDetailsCollapsed = false
    #if DEBUG
        @AppStorage("debug.locale.override") private var debugLocaleOverride = "system"
    #endif

    private let service: Servicing = RemoteService()

    private var selectedSection: WorkspaceSection {
        get {
            WorkspaceSection(rawValue: selectedSectionRawValue) ?? .notes
        }
        nonmutating set {
            selectedSectionRawValue = newValue.rawValue
        }
    }

    private var translationTaskID: String {
        #if DEBUG
            return debugLocaleOverride
        #else
            return Locale.preferredLanguages.first ?? "system"
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isLoggedIn {
                VStack(spacing: 8) {
                    ForEach(WorkspaceSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            Image(systemName: section.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .foregroundStyle(selectedSection == section ? .primary : .secondary)
                                .background(
                                    selectedSection == section
                                        ? Color.primary.opacity(0.12) : .clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(section.title)
                    }

                    Spacer(minLength: 0)

                    Button {
                        showDataProtectionDialog = true
                    } label: {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.primary)
                            .background(Color.primary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("dataProtection.title"))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .frame(
                    minWidth: 56,
                    idealWidth: 56,
                    maxWidth: 56,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .background(.quaternary.opacity(0.35))

                Divider()
            }

            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 16) {
                            headerView

                            if isLoggedIn {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        Text(L10n.s("user.details"))
                                            .font(.headline)

                                        Spacer()

                                        Button {
                                            isUserDetailsCollapsed.toggle()
                                        } label: {
                                            Image(
                                                systemName: isUserDetailsCollapsed
                                                    ? "chevron.down.circle" : "chevron.up.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .help(
                                            isUserDetailsCollapsed
                                                ? L10n.s("user.details.expand")
                                                : L10n.s("user.details.collapse"))
                                    }

                                    if !isUserDetailsCollapsed {
                                        LoggedInUserDetailsView(
                                            displayName: displayName,
                                            email: userInfo?.email,
                                            profileImageURL: profileImageURL,
                                            lastLoginText: lastLoginText,
                                            registeredText: registeredText,
                                            hasDataProtectionSecurityKey: hasDataProtectionSecurityKey,
                                            isLoggingOut: isLoggingOut,
                                            onDataProtectionTap: {
                                                showDataProtectionDialog = true
                                            },
                                            onLogoutTap: {
                                                Task {
                                                    await logoutCurrentUser()
                                                }
                                            })
                                    }
                                }
                            } else if isCheckingStoredSession {
                                ProgressView(L10n.s("session.validating"))
                                    .controlSize(.small)
                            }

                            if !isLoggedIn {
                                Button(L10n.s("login.title")) {
                                    showLoginDialog = true
                                }
                            }

                            if isLoggedIn {
                                Divider()

                                sectionSkeletonView
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .topLeading)
                            }
                        }
                        .padding(24)
                        .frame(minHeight: proxy.size.height, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .scrollIndicators(.automatic)
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(activityStatusMessage ?? statusBarMessage ?? L10n.s("status.ready"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.2))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 700, minHeight: 420)
        .sheet(isPresented: $showLoginDialog) {
            LoginDialogView(
                isPresented: $showLoginDialog,
                onAuthenticated: { (authentication, userInfo) in
                    isLoggedIn = true
                    self.authentication = authentication
                    self.userInfo = userInfo
                    restoreDataProtectionKeyFromSession(for: userInfo)
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
        .sheet(isPresented: $showDataProtectionDialog) {
            DataProtectionDialogView(
                isPresented: $showDataProtectionDialog,
                initialSecurityKey: dataProtectionSecurityKey,
                onSave: { securityKey in
                    saveDataProtectionSecurityKey(securityKey)
                })
        }
        .task(id: translationTaskID) {
            await initializeTranslationsOnStartup()
        }
        .task {
            await authenticateStoredSessionOnStartup()
        }
        .onDisappear {
            clearStatusBarTask?.cancel()
            clearStatusBarTask = nil
        }
    }

    @MainActor
    private func initializeTranslationsOnStartup() async {
        do {
            let supportedLocale = L10n.supportedLanguageCode()
            try await service.initializeTranslations(locale: supportedLocale)
        } catch {
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
            let authentication = try await service.authenticateLongLivedToken(
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
            let userInfo = try await service.getUserInfo(token: token)
            self.authentication = authentication
            self.userInfo = userInfo
            self.isLoggedIn = true
            restoreDataProtectionKeyFromSession(for: userInfo)
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
            throw ServiceError.twoFactorTokenMissing
        }
        let authentication = try await service.completePin(
            longLivedToken: token, pin: pin)
        guard let token = authentication.token
        else {
            throw ServiceError.serverError(
                L10n.s("error.pin.noAccessToken"))
        }
        let userInfo = try await service.getUserInfo(token: token)
        self.authentication = authentication
        self.userInfo = userInfo
        self.isLoggedIn = true
        restoreDataProtectionKeyFromSession(for: userInfo)
        pendingLongLivedTokenForPin = nil
        AuthSessionStore.shared.save(from: authentication)
    }

    private func restoreDataProtectionKeyFromSession(for userInfo: UserInfoResponse) {
        if let restored = AuthSessionStore.shared.loadDataProtectionSecurityKey(
            userID: userInfo.id,
            passwordManagerSalt: userInfo.passwordManagerSalt)
        {
            dataProtectionSecurityKey = restored
        } else {
            dataProtectionSecurityKey = ""
        }
    }

    private func saveDataProtectionSecurityKey(_ securityKey: String) {
        guard isLoggedIn,
            let userID = userInfo?.id,
            let salt = userInfo?.passwordManagerSalt,
            !salt.isEmpty
        else {
            return
        }
        dataProtectionSecurityKey = securityKey
        AuthSessionStore.shared.saveDataProtectionSecurityKey(
            dataProtectionSecurityKey,
            userID: userID,
            passwordManagerSalt: salt)
    }

    @MainActor
    private func logoutCurrentUser() async {
        guard !isLoggingOut else {
            return
        }
        isLoggingOut = true
        defer { isLoggingOut = false }
        if let token = authentication?.token, !token.isEmpty {
            do {
                try await service.logout(token: token)
            } catch {
            }
        }
        AuthSessionStore.shared.clear()
        self.isLoggedIn = false
        self.authentication = nil
        self.userInfo = nil
        self.dataProtectionSecurityKey = ""
    }

    private var displayName: String {
        guard let name = userInfo?.name, !name.isEmpty else {
            return L10n.s("user.loggedIn")
        }
        return name
    }

    private var profileImageURL: URL? {
        guard let photo = userInfo?.photo,
            !photo.isEmpty
        else {
            return nil
        }
        return URL(string: photo, relativeTo: URL(string: "https://www.stockfleth.eu"))
    }

    private var lastLoginText: String? {
        guard let lastLoginUtc = userInfo?.lastLoginUtc else {
            return nil
        }
        return DateFormattingUtility.displayDate(fromUTCISOString: lastLoginUtc)
    }

    private var registeredText: String? {
        guard let registeredUtc = userInfo?.registeredUtc else {
            return nil
        }
        return DateFormattingUtility.displayDate(fromUTCISOString: registeredUtc)
    }

    private var hasDataProtectionSecurityKey: Bool {
        !dataProtectionSecurityKey.isEmpty
    }

    @ViewBuilder
    private var sectionSkeletonView: some View {
        switch selectedSection {
        case .notes:
            NotesView(
                service: service,
                authentication: authentication,
                passwordManagerSalt: userInfo?.passwordManagerSalt,
                dataProtectionSecurityKey: dataProtectionSecurityKey,
                isLoggedIn: isLoggedIn,
                onActivityStatusChange: { message in
                    setActivityStatusBarMessage(message)
                })
        case .documents:
            SectionSkeletonView(
                title: L10n.s("section.documents"),
                subtitle: L10n.s("section.documents.subtitle"))
        case .passwords:
            PasswordsView(
                service: service,
                authentication: authentication,
                userInfo: userInfo,
                dataProtectionSecurityKey: dataProtectionSecurityKey,
                isLoggedIn: isLoggedIn,
                onActivityStatusChange: { message in
                    setActivityStatusBarMessage(message)
                },
                onStatusMessage: { message in
                    showStatusBarMessage(message)
                })
        case .contacts:
            ContactsView(
                service: service,
                authentication: authentication,
                userInfo: userInfo,
                dataProtectionSecurityKey: dataProtectionSecurityKey,
                isLoggedIn: isLoggedIn,
                onActivityStatusChange: { message in
                    setActivityStatusBarMessage(message)
                })
        case .appointments:
            SectionSkeletonView(
                title: L10n.s("section.appointments"),
                subtitle: L10n.s("section.appointments.subtitle"))
        case .diaryEntries:
            DiaryView(
                service: service,
                authentication: authentication,
                userInfo: userInfo,
                dataProtectionSecurityKey: dataProtectionSecurityKey,
                isLoggedIn: isLoggedIn,
                onActivityStatusChange: { message in
                    setActivityStatusBarMessage(message)
                },
                onStatusMessage: { message in
                    showStatusBarMessage(message)
                })
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.s("workspace.title"))
                .font(.largeTitle)
            Text(L10n.s("workspace.subtitle"))
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func showStatusBarMessage(_ message: String) {
        statusBarMessage = message
        clearStatusBarTask?.cancel()
        clearStatusBarTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled {
                return
            }
            await MainActor.run {
                statusBarMessage = nil
            }
        }
    }

    @MainActor
    private func setActivityStatusBarMessage(_ message: String?) {
        activityStatusMessage = message
    }

}

private struct SectionSkeletonView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(height: 38)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(height: 120)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 90)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 90)
            }
        }
    }
}
