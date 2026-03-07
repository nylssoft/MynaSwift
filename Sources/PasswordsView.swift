import AppKit
import SwiftUI

struct PasswordsView: View {
    private let hiddenPasswordMask = "*********"

    let service: Servicing
    let authentication: AuthenticationResponse?
    let userInfo: UserInfoResponse?
    let dataProtectionSecurityKey: String
    let isLoggedIn: Bool
    let onActivityStatusChange: (String?) -> Void
    let onStatusMessage: (String) -> Void

    @State private var passwordItems: [PasswordItem] = []
    @State private var isLoadingPasswords = false
    @State private var isUploadingPasswords = false
    @State private var passwordsErrorMessage: String?
    @State private var hasLoadedPasswords = false
    @State private var hasUploadedPasswordFile = false

    @State private var selectedPasswordID: UUID?
    @State private var isEditingSelection = false
    @State private var passwordNameDraft = ""
    @State private var passwordURLDraft = ""
    @State private var passwordLoginDraft = ""
    @State private var passwordDescriptionDraft = ""
    @State private var passwordDraft = ""
    @State private var encryptedPasswordDraft = ""
    @State private var isPasswordVisible = false
    @State private var showDeleteConfirmation = false

    private var token: String? {
        authentication?.token
    }

    private var passwordManagerSalt: String? {
        userInfo?.passwordManagerSalt
    }

    private var hasPasswordFileOnServer: Bool {
        hasUploadedPasswordFile || (userInfo?.hasPasswordManagerFile ?? false)
    }

    private var canSyncPasswords: Bool {
        guard isLoggedIn,
            let token,
            !token.isEmpty,
            let passwordManagerSalt,
            !passwordManagerSalt.isEmpty,
            !dataProtectionSecurityKey.isEmpty
        else {
            return false
        }
        return true
    }

    private var isBusy: Bool {
        isLoadingPasswords || isUploadingPasswords
    }

    private var selectedPasswordItem: PasswordItem? {
        guard let selectedPasswordID else {
            return nil
        }
        return passwordItems.first { $0.id == selectedPasswordID }
    }

    private var sortedPasswordItems: [PasswordItem] {
        passwordItems.sorted(by: sortPasswordsByName)
    }

    private var syncContextID: String {
        "\(isLoggedIn)|\(token ?? "")|\(passwordManagerSalt ?? "")|\(dataProtectionSecurityKey)|\(userInfo?.hasPasswordManagerFile == true)"
    }

    private var selectedPasswordDisplayName: String {
        guard let selectedPasswordItem else {
            return L10n.s("passwords.thisPassword")
        }
        return selectedPasswordItem.name.isEmpty
            ? L10n.s("passwords.thisPassword")
            : selectedPasswordItem.name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.s("section.passwords"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        Task {
                            await loadPasswordItemsIfNeeded(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("passwords.reload"))
                    .disabled(isBusy || !isLoggedIn)

                    Button {
                        Task {
                            await createPasswordItem()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("passwords.add"))
                    .disabled(isBusy || !canSyncPasswords)
                }

                if let passwordsErrorMessage {
                    Text(passwordsErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if passwordItems.isEmpty {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 2)
                } else {
                    List(sortedPasswordItems) { item in
                        Button {
                            selectPassword(item)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                FaviconView(url: faviconURL(from: item.url))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        item.name.isEmpty
                                            ? L10n.s("passwords.noName") : item.name
                                    )
                                    .font(.headline)

                                    if !item.login.isEmpty || !item.url.isEmpty {
                                        Text(item.login.isEmpty ? item.url : item.login)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedPasswordID == item.id
                                ? Color.primary.opacity(0.12) : Color.clear
                        )
                        .disabled(isBusy)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300)

            Divider()

            PasswordDetailView(
                passwordItem: selectedPasswordItem,
                isBusy: isBusy,
                isEditing: isEditingSelection,
                isPasswordVisible: isPasswordVisible,
                hiddenPasswordMask: hiddenPasswordMask,
                faviconURL: faviconURL(from: passwordURLDraft),
                nameDraft: $passwordNameDraft,
                urlDraft: $passwordURLDraft,
                loginDraft: $passwordLoginDraft,
                descriptionDraft: $passwordDescriptionDraft,
                passwordDraft: $passwordDraft,
                hasEncryptedPassword: !encryptedPasswordDraft.isEmpty,
                onOpenURL: {
                    openCurrentURL()
                },
                onCopyLogin: {
                    copyToClipboard(
                        passwordLoginDraft,
                        successText: L10n.s("passwords.status.copiedLogin"))
                },
                onCopyPassword: {
                    Task {
                        await copyCurrentPasswordToClipboard()
                    }
                },
                onToggleEdit: {
                    Task {
                        await toggleEditSelection()
                    }
                },
                onDelete: {
                    showDeleteConfirmation = true
                },
                onTogglePasswordVisibility: {
                    Task {
                        await togglePasswordVisibility()
                    }
                })
        }
        .alert(L10n.s("passwords.delete.title"), isPresented: $showDeleteConfirmation) {
            Button(L10n.s("common.cancel"), role: .cancel) {}
            Button(L10n.s("common.delete"), role: .destructive) {
                Task {
                    await deleteSelectedPasswordItem()
                }
            }
        } message: {
            Text(
                String(
                    format: L10n.s("passwords.delete.message.format"),
                    selectedPasswordDisplayName))
        }
        .task(id: syncContextID) {
            hasLoadedPasswords = false
            hasUploadedPasswordFile = false
            clearSelection()
            await loadPasswordItemsIfNeeded(force: true)
        }
    }

    private var emptyStateMessage: String {
        if !hasPasswordFileOnServer {
            return L10n.s("passwords.empty.noFile")
        }
        return L10n.s("passwords.empty")
    }

    @MainActor
    private func loadPasswordItemsIfNeeded(force: Bool, preferredSelectedID: UUID? = nil) async {
        if isLoadingPasswords {
            return
        }
        if hasLoadedPasswords && !force {
            return
        }
        guard canSyncPasswords,
            let token,
            let passwordManagerSalt
        else {
            passwordsErrorMessage = L10n.s("passwords.error.setKey.load")
            passwordItems = []
            hasLoadedPasswords = false
            clearSelection()
            return
        }

        if !hasPasswordFileOnServer {
            passwordsErrorMessage = nil
            passwordItems = []
            hasLoadedPasswords = true
            clearSelection()
            return
        }

        isLoadingPasswords = true
        onActivityStatusChange(L10n.s("passwords.loading"))
        passwordsErrorMessage = nil
        defer {
            isLoadingPasswords = false
            onActivityStatusChange(nil)
        }

        do {
            let items = try await service.getPasswordItems(
                token: token,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            passwordItems = items.sorted(by: sortPasswordsByName)
            hasLoadedPasswords = true
            updateSelectionAfterReload(preferredSelectedID: preferredSelectedID)
        } catch {
            passwordsErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? L10n.s("passwords.error.load")
            passwordItems = []
            hasLoadedPasswords = false
            clearSelection()
        }
    }

    @MainActor
    private func uploadPasswordItems() async {
        if isUploadingPasswords {
            return
        }
        guard canSyncPasswords,
            let token,
            let passwordManagerSalt
        else {
            passwordsErrorMessage = L10n.s("passwords.error.setKey.upload")
            return
        }

        isUploadingPasswords = true
        onActivityStatusChange(L10n.s("passwords.uploading"))
        passwordsErrorMessage = nil
        defer {
            isUploadingPasswords = false
            onActivityStatusChange(nil)
        }

        do {
            try await service.savePasswordItems(
                token: token,
                passwordItems: passwordItems,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            hasUploadedPasswordFile = true
        } catch {
            passwordsErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? L10n.s("passwords.error.upload")
        }
    }

    @MainActor
    private func createPasswordItem() async {
        guard canSyncPasswords else {
            passwordsErrorMessage = L10n.s("passwords.error.setKey.create")
            return
        }
        let newItem = PasswordItem(
            name: "",
            url: "",
            login: "",
            description: "",
            password: "")
        passwordItems.append(newItem)
        passwordItems.sort(by: sortPasswordsByName)
        selectPassword(newItem)
        isEditingSelection = true
        await uploadAndReload(preferredSelectedID: newItem.id)
    }

    @MainActor
    private func toggleEditSelection() async {
        guard selectedPasswordItem != nil else {
            return
        }
        if isEditingSelection {
            await saveSelectedPasswordChanges()
        } else {
            isEditingSelection = true
        }
    }

    @MainActor
    private func saveSelectedPasswordChanges() async {
        guard let selectedPasswordID,
            let index = passwordItems.firstIndex(where: { $0.id == selectedPasswordID }),
            let token,
            let passwordManagerSalt
        else {
            return
        }

        passwordItems[index].name = passwordNameDraft
        passwordItems[index].url = passwordURLDraft
        passwordItems[index].login = passwordLoginDraft
        passwordItems[index].description = passwordDescriptionDraft

        do {
            if passwordDraft.isEmpty {
                passwordItems[index].password = ""
            } else if !isPasswordVisible && passwordDraft == hiddenPasswordMask {
                // Keep the existing encrypted value when the masked sentinel is unchanged.
                passwordItems[index].password = encryptedPasswordDraft
            } else {
                passwordItems[index].password = try await service.encodePassword(
                    token: token,
                    password: passwordDraft,
                    encryptionKey: dataProtectionSecurityKey,
                    passwordManagerSalt: passwordManagerSalt)
            }
            isEditingSelection = false
            await uploadAndReload(preferredSelectedID: selectedPasswordID)
        } catch {
            passwordsErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? L10n.s("passwords.error.encode")
        }
    }

    @MainActor
    private func deleteSelectedPasswordItem() async {
        guard let selectedPasswordID else {
            return
        }
        passwordItems.removeAll { $0.id == selectedPasswordID }
        clearSelection()
        await uploadAndReload(preferredSelectedID: nil)
    }

    @MainActor
    private func togglePasswordVisibility() async {
        guard selectedPasswordItem != nil else {
            return
        }
        if isPasswordVisible {
            isPasswordVisible = false
            return
        }

        guard !encryptedPasswordDraft.isEmpty else {
            isPasswordVisible = true
            return
        }

        // Mirror MAUI behavior: decode only when the hidden sentinel is still present.
        if passwordDraft != hiddenPasswordMask {
            isPasswordVisible = true
            return
        }

        guard canSyncPasswords,
            let token,
            let passwordManagerSalt
        else {
            passwordsErrorMessage = L10n.s("passwords.error.setKey.decode")
            return
        }

        do {
            let plainPassword = try await service.decodePassword(
                token: token,
                encryptedPassword: encryptedPasswordDraft,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            passwordDraft = plainPassword
            isPasswordVisible = true
        } catch {
            passwordsErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? L10n.s("passwords.error.decode")
        }
    }

    @MainActor
    private func uploadAndReload(preferredSelectedID: UUID?) async {
        await uploadPasswordItems()
        if passwordsErrorMessage == nil {
            passwordItems.sort(by: sortPasswordsByName)
            updateSelectionAfterReload(preferredSelectedID: preferredSelectedID)
        }
    }

    private func selectPassword(_ item: PasswordItem) {
        selectedPasswordID = item.id
        passwordNameDraft = item.name
        passwordURLDraft = item.url
        passwordLoginDraft = item.login
        passwordDescriptionDraft = item.description
        encryptedPasswordDraft = item.password
        passwordDraft = item.password.isEmpty ? "" : hiddenPasswordMask
        isPasswordVisible = false
        isEditingSelection = false
        passwordsErrorMessage = nil
    }

    private func updateSelectionAfterReload(preferredSelectedID: UUID?) {
        let targetID = preferredSelectedID ?? selectedPasswordID
        guard let targetID,
            let selected = passwordItems.first(where: { $0.id == targetID })
        else {
            if passwordItems.isEmpty {
                clearSelection()
            }
            return
        }
        selectPassword(selected)
    }

    private func clearSelection() {
        selectedPasswordID = nil
        isEditingSelection = false
        passwordNameDraft = ""
        passwordURLDraft = ""
        passwordLoginDraft = ""
        passwordDescriptionDraft = ""
        passwordDraft = ""
        encryptedPasswordDraft = ""
        isPasswordVisible = false
    }

    private func showStatusMessage(_ message: String) {
        onStatusMessage(message)
    }

    private func copyToClipboard(_ text: String, successText: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showStatusMessage(successText)
    }

    @MainActor
    private func copyCurrentPasswordToClipboard() async {
        if passwordDraft.isEmpty && encryptedPasswordDraft.isEmpty {
            copyToClipboard("", successText: L10n.s("passwords.status.copiedPassword"))
            return
        }

        if isEditingSelection && !isPasswordVisible && passwordDraft != hiddenPasswordMask {
            copyToClipboard(passwordDraft, successText: L10n.s("passwords.status.copiedPassword"))
            return
        }

        if isPasswordVisible {
            copyToClipboard(passwordDraft, successText: L10n.s("passwords.status.copiedPassword"))
            return
        }

        guard canSyncPasswords,
            let token,
            let passwordManagerSalt
        else {
            passwordsErrorMessage = L10n.s("passwords.error.setKey.decode")
            return
        }

        do {
            let plainPassword = try await service.decodePassword(
                token: token,
                encryptedPassword: encryptedPasswordDraft,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            copyToClipboard(
                plainPassword,
                successText: L10n.s("passwords.status.copiedPassword"))
        } catch {
            passwordsErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? L10n.s("passwords.error.decode")
        }
    }

    private func openCurrentURL() {
        guard let url = normalizedURL(from: passwordURLDraft) else {
            passwordsErrorMessage = L10n.s("passwords.error.invalidURL")
            return
        }
        let opened = NSWorkspace.shared.open(url)
        if opened {
            showStatusMessage(L10n.s("passwords.status.openedURL"))
        } else {
            passwordsErrorMessage = L10n.s("passwords.error.invalidURL")
        }
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: "https://\(trimmed)")
    }

    private func faviconURL(from rawValue: String) -> URL? {
        guard let targetURL = normalizedURL(from: rawValue),
            let host = targetURL.host,
            !host.isEmpty
        else {
            return nil
        }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)")
    }

    private func sortPasswordsByName(_ lhs: PasswordItem, _ rhs: PasswordItem) -> Bool {
        let name1 = lhs.name.localizedLowercase
        let name2 = rhs.name.localizedLowercase
        if name1 == name2 {
            let left =
                "\(lhs.login)|\(lhs.url)|\(lhs.description)|\(lhs.password)".localizedLowercase
            let right =
                "\(rhs.login)|\(rhs.url)|\(rhs.description)|\(rhs.password)".localizedLowercase
            return left < right
        }
        return name1 < name2
    }
}

private struct PasswordDetailView: View {
    let passwordItem: PasswordItem?
    let isBusy: Bool
    let isEditing: Bool
    let isPasswordVisible: Bool
    let hiddenPasswordMask: String
    let faviconURL: URL?
    @Binding var nameDraft: String
    @Binding var urlDraft: String
    @Binding var loginDraft: String
    @Binding var descriptionDraft: String
    @Binding var passwordDraft: String
    let hasEncryptedPassword: Bool
    let onOpenURL: () -> Void
    let onCopyLogin: () -> Void
    let onCopyPassword: () -> Void
    let onToggleEdit: () -> Void
    let onDelete: () -> Void
    let onTogglePasswordVisibility: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    FaviconView(url: faviconURL)
                    Text(passwordTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                Button(action: onToggleEdit) {
                    Image(systemName: isEditing ? "checkmark" : "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help(
                    isEditing
                        ? L10n.s("passwords.help.saveChanges")
                        : L10n.s("passwords.help.edit")
                )
                .disabled(passwordItem == nil || isBusy)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help(L10n.s("passwords.delete"))
                .disabled(passwordItem == nil || isBusy)
            }

            if passwordItem == nil {
                Text(L10n.s("passwords.selectPrompt"))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Group {
                    if isEditing {
                        editableRow(label: L10n.s("passwords.field.name"), text: $nameDraft)
                        editableRow(
                            label: L10n.s("passwords.field.url"),
                            text: $urlDraft,    
                            trailingActions: {
                                Button(action: onOpenURL) {
                                    Image(systemName: "safari")
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("passwords.openURL"))
                                .disabled(passwordItem == nil || isBusy || urlDraft.isEmpty)
                            })
                        editableRow(
                            label: L10n.s("passwords.field.login"),
                            text: $loginDraft,
                            trailingActions: {
                                Button(action: onCopyLogin) {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("passwords.copyLogin"))
                                .disabled(passwordItem == nil || isBusy || loginDraft.isEmpty)
                            })
                    } else {
                        readOnlyRow(
                            label: L10n.s("passwords.field.url"),
                            value: urlDraft,
                            trailingActions: {
                                Button(action: onOpenURL) {
                                    Image(systemName: "safari")
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("passwords.openURL"))
                                .disabled(passwordItem == nil || isBusy || urlDraft.isEmpty)
                            })
                        readOnlyRow(
                            label: L10n.s("passwords.field.login"),
                            value: loginDraft,
                            trailingActions: {
                                Button(action: onCopyLogin) {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("passwords.copyLogin"))
                                .disabled(passwordItem == nil || isBusy || loginDraft.isEmpty)
                            })
                    }
                }

                passwordRow
                descriptionRow

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var passwordTitle: String {
        guard let passwordItem else {
            return L10n.s("passwords.password")
        }
        return passwordItem.name.isEmpty ? L10n.s("passwords.noName") : passwordItem.name
    }

    private var passwordRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.s("passwords.field.password"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(action: onCopyPassword) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help(L10n.s("passwords.copyPassword"))
                .disabled(passwordItem == nil || isBusy || (passwordDraft.isEmpty && !hasEncryptedPassword))

                Button(action: onTogglePasswordVisibility) {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .help(
                    isPasswordVisible
                        ? L10n.s("passwords.hide")
                        : L10n.s("passwords.show")
                )
                .disabled(passwordItem == nil || isBusy || (!hasEncryptedPassword && !isEditing))
            }

            if isEditing {
                if isPasswordVisible {
                    TextField(L10n.s("passwords.field.password"), text: $passwordDraft)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField(L10n.s("passwords.field.password"), text: $passwordDraft)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Text(passwordDisplayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var descriptionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.s("passwords.field.description"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEditing {
                TextEditor(text: $descriptionDraft)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(readOnlyText(descriptionDraft))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var passwordDisplayText: String {
        if isPasswordVisible {
            return readOnlyText(passwordDraft)
        }
        if hasEncryptedPassword {
            return hiddenPasswordMask
        }
        return L10n.s("common.notSet")
    }

    @ViewBuilder
    private func editableRow<TrailingActions: View>(
        label: String,
        text: Binding<String>,
        @ViewBuilder trailingActions: () -> TrailingActions
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                trailingActions()
            }

            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func editableRow(label: String, text: Binding<String>) -> some View {
        editableRow(label: label, text: text) {
            EmptyView()
        }
    }

    @ViewBuilder
    private func readOnlyRow<TrailingActions: View>(
        label: String,
        value: String,
        @ViewBuilder trailingActions: () -> TrailingActions
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                trailingActions()
            }

            Text(readOnlyText(value))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private func readOnlyRow(label: String, value: String) -> some View {
        readOnlyRow(label: label, value: value) {
            EmptyView()
        }
    }

    private func readOnlyText(_ value: String) -> String {
        value.isEmpty ? L10n.s("common.notSet") : value
    }
}

private struct FaviconView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                    case .failure:
                        fallbackImage
                    case .empty:
                        fallbackImage
                    @unknown default:
                        fallbackImage
                    }
                }
            } else {
                fallbackImage
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var fallbackImage: some View {
        Image(systemName: "key.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(2)
            .background(Color.primary.opacity(0.08))
    }
}
