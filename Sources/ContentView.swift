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
                return "Notes"
            case .documents:
                return "Documents"
            case .passwords:
                return "Passwords"
            case .contacts:
                return "Contacts"
            case .appointments:
                return "Appointments"
            case .diaryEntries:
                return "Diary Entries"
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
    @State private var selectedSection: WorkspaceSection = .notes
    @State private var showDataProtectionDialog = false
    @State private var dataProtectionSecurityKey = ""
    @State private var isLoggingOut = false
    @State private var contactItems: [ContactItem] = []
    @State private var isLoadingContacts = false
    @State private var isUploadingContacts = false
    @State private var contactsErrorMessage: String?
    @State private var hasLoadedContacts = false
    @State private var selectedContactID: Int64?
    @State private var contactNameDraft = ""
    @State private var contactBirthdayDraft = ""
    @State private var contactPhoneDraft = ""
    @State private var contactAddressDraft = ""
    @State private var contactEmailDraft = ""
    @State private var contactNoteDraft = ""

    private let service: Servicing = RemoteService()

    var body: some View {
        HStack(spacing: 0) {
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
                                selectedSection == section ? Color.primary.opacity(0.12) : .clear
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
                        .foregroundStyle(isLoggedIn ? .primary : .secondary)
                        .background(Color.primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Data Protection")
                .disabled(!isLoggedIn)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .frame(width: 56)
            .background(.quaternary.opacity(0.35))

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                headerView

                if isLoggedIn {
                    userDetailsView
                } else if isCheckingStoredSession {
                    ProgressView("Validating saved session...")
                        .controlSize(.small)
                }

                HStack(spacing: 10) {
                    Button(isLoggedIn ? "Switch User" : "Login") {
                        showLoginDialog = true
                    }
                }

                Divider()

                sectionSkeletonView

                Spacer(minLength: 0)
            }
            .padding(24)
        }
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
        .task {
            await initializeTranslationsOnStartup()
            await authenticateStoredSessionOnStartup()
        }
        .task(id: selectedSection) {
            guard selectedSection == .contacts else {
                return
            }
            await loadContactItemsIfNeeded(force: false)
        }
    }

    @MainActor
    private func initializeTranslationsOnStartup() async {
        do {
            try await service.initializeTranslations(locale: "en")
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
                "PIN authentication did not return an access token.")
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
        self.contactItems = []
        self.contactsErrorMessage = nil
        self.hasLoadedContacts = false
        clearContactSelection()
    }

    @MainActor
    private func loadContactItemsIfNeeded(force: Bool) async {
        if isLoadingContacts {
            return
        }
        if hasLoadedContacts && !force {
            return
        }
        guard let token = authentication?.token,
            !token.isEmpty,
            let salt = userInfo?.passwordManagerSalt,
            !salt.isEmpty,
            !dataProtectionSecurityKey.isEmpty
        else {
            contactsErrorMessage = "Set your data protection key to load contacts."
            contactItems = []
            hasLoadedContacts = false
            return
        }

        isLoadingContacts = true
        contactsErrorMessage = nil
        defer { isLoadingContacts = false }

        do {
            let items = try await service.getContactItems(
                token: token,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: salt)
            contactItems = items
            hasLoadedContacts = true
            clearContactSelection()
        } catch {
            contactsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Failed to load contacts."
            contactItems = []
            hasLoadedContacts = false
            clearContactSelection()
        }
    }

    @MainActor
    private func uploadContactItems() async {
        if isUploadingContacts {
            return
        }
        guard let token = authentication?.token,
            !token.isEmpty,
            let salt = userInfo?.passwordManagerSalt,
            !salt.isEmpty,
            !dataProtectionSecurityKey.isEmpty
        else {
            contactsErrorMessage = "Set your data protection key to upload contacts."
            return
        }

        isUploadingContacts = true
        contactsErrorMessage = nil
        defer { isUploadingContacts = false }

        do {
            try await service.uploadContactItems(
                token: token,
                contactItems: contactItems,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: salt)
        } catch {
            contactsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Failed to upload contacts."
        }
    }

    private func clearContactSelection() {
        selectedContactID = nil
        contactNameDraft = ""
        contactBirthdayDraft = ""
        contactPhoneDraft = ""
        contactAddressDraft = ""
        contactEmailDraft = ""
        contactNoteDraft = ""
    }

    private func selectContact(_ item: ContactItem) {
        selectedContactID = item.id
        contactNameDraft = item.name
        contactBirthdayDraft = item.birthday
        contactPhoneDraft = item.phone
        contactAddressDraft = item.address
        contactEmailDraft = item.email
        contactNoteDraft = item.note
    }

    private func createContact() {
        let nextID = (contactItems.map(\.id).max() ?? 0) + 1
        let newContact = ContactItem(
            id: nextID,
            name: "",
            birthday: "",
            phone: "",
            address: "",
            email: "",
            note: "")
        contactItems.append(newContact)
        contactItems.sort { $0.id < $1.id }
        selectContact(newContact)
    }

    private func saveSelectedContactChanges() {
        guard let selectedContactID,
            let index = contactItems.firstIndex(where: { $0.id == selectedContactID })
        else {
            return
        }
        contactItems[index].name = contactNameDraft
        contactItems[index].birthday = contactBirthdayDraft
        contactItems[index].phone = contactPhoneDraft
        contactItems[index].address = contactAddressDraft
        contactItems[index].email = contactEmailDraft
        contactItems[index].note = contactNoteDraft
        contactsErrorMessage = nil
    }

    private func deleteSelectedContact() {
        guard let selectedContactID else {
            return
        }
        contactItems.removeAll { $0.id == selectedContactID }
        clearContactSelection()
        contactsErrorMessage = nil
    }

    private var displayName: String {
        guard let name = userInfo?.name, !name.isEmpty else {
            return "Logged in"
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

    private var hasDataProtectionSecurityKey: Bool {
        !dataProtectionSecurityKey.isEmpty
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

    @ViewBuilder
    private var sectionSkeletonView: some View {
        switch selectedSection {
        case .notes:
            SectionSkeletonView(title: "Notes", subtitle: "Manage all notes")
        case .documents:
            SectionSkeletonView(title: "Documents", subtitle: "Manage all documents")
        case .passwords:
            SectionSkeletonView(title: "Passwords", subtitle: "Manage all passwords")
        case .contacts:
            contactsSectionView
        case .appointments:
            SectionSkeletonView(title: "Appointments", subtitle: "Manage all appointments")
        case .diaryEntries:
            SectionSkeletonView(title: "Diary Entries", subtitle: "Manage all diary entries")
        }
    }

    private var contactsSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contacts")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Manage encrypted contact items")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reload") {
                    Task {
                        await loadContactItemsIfNeeded(force: true)
                    }
                }
                .disabled(isLoadingContacts || !isLoggedIn)

                Button("Upload") {
                    Task {
                        await uploadContactItems()
                    }
                }
                .disabled(isUploadingContacts || isLoadingContacts || !isLoggedIn)
            }

            if isLoadingContacts || isUploadingContacts {
                ProgressView(isUploadingContacts ? "Uploading contacts..." : "Loading contacts...")
                    .controlSize(.small)
            }

            if let contactsErrorMessage {
                Text(contactsErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if contactItems.isEmpty {
                Text("No contacts available.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                List(contactItems) { item in
                    Button {
                        selectContact(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name.isEmpty ? "(No name)" : item.name)
                                .font(.headline)
                            if !item.email.isEmpty {
                                Text(item.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !item.phone.isEmpty {
                                Text(item.phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedContactID == item.id ? Color.primary.opacity(0.12) : Color.clear
                    )
                }
                .frame(minHeight: 170)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("New") {
                        createContact()
                    }
                    .disabled(!isLoggedIn || isLoadingContacts || isUploadingContacts)

                    Button("Save Changes") {
                        saveSelectedContactChanges()
                    }
                    .disabled(selectedContactID == nil || isLoadingContacts || isUploadingContacts)

                    Button("Delete") {
                        deleteSelectedContact()
                    }
                    .disabled(selectedContactID == nil || isLoadingContacts || isUploadingContacts)
                }

                TextField("Name", text: $contactNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedContactID == nil)
                HStack(spacing: 10) {
                    TextField("Birthday", text: $contactBirthdayDraft)
                        .textFieldStyle(.roundedBorder)
                        .disabled(selectedContactID == nil)
                    TextField("Phone", text: $contactPhoneDraft)
                        .textFieldStyle(.roundedBorder)
                        .disabled(selectedContactID == nil)
                }
                TextField("Email", text: $contactEmailDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedContactID == nil)
                TextField("Address", text: $contactAddressDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedContactID == nil)
                TextField("Note", text: $contactNoteDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedContactID == nil)
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Personal Workspace")
                .font(.largeTitle)
            Text(
                "Organize your notes, documents, passwords, contacts, appointments, and diary entries in one place."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var userDetailsView: some View {
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

                Button {
                    showDataProtectionDialog = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasDataProtectionSecurityKey ? "lock.fill" : "lock.open")
                            .font(.caption)
                        Text(
                            hasDataProtectionSecurityKey
                                ? "Data protection key: Set" : "Data protection key: Not set"
                        )
                        .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button("Log out") {
                    Task {
                        await logoutCurrentUser()
                    }
                }
                .font(.caption)
                .buttonStyle(.link)
                .disabled(isLoggingOut)
            }
        }
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
