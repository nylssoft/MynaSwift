import SwiftUI

struct ContactsView: View {
    let service: Servicing
    let authentication: AuthenticationResponse?
    let userInfo: UserInfoResponse?
    let dataProtectionSecurityKey: String
    let isLoggedIn: Bool

    @State private var contactItems: [ContactItem] = []
    @State private var isLoadingContacts = false
    @State private var isUploadingContacts = false
    @State private var contactsErrorMessage: String?
    @State private var hasLoadedContacts = false
    @State private var selectedContactID: Int64?
    @State private var isEditingSelection = false
    @State private var contactNameDraft = ""
    @State private var contactBirthdayDraft = ""
    @State private var contactPhoneDraft = ""
    @State private var contactAddressDraft = ""
    @State private var contactEmailDraft = ""
    @State private var contactNoteDraft = ""
    @State private var showDeleteConfirmation = false

    private var token: String? {
        authentication?.token
    }

    private var passwordManagerSalt: String? {
        userInfo?.passwordManagerSalt
    }

    private var canSyncContacts: Bool {
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
        isLoadingContacts || isUploadingContacts
    }

    private var selectedContact: ContactItem? {
        guard let selectedContactID else {
            return nil
        }
        return contactItems.first { $0.id == selectedContactID }
    }

    private var sortedContactItems: [ContactItem] {
        contactItems.sorted(by: sortContactsByName)
    }

    private var syncContextID: String {
        "\(isLoggedIn)|\(token ?? "")|\(passwordManagerSalt ?? "")|\(dataProtectionSecurityKey)"
    }

    private var selectedContactDisplayName: String {
        guard let selectedContact else {
            return L10n.s("contacts.thisContact")
        }
        return selectedContact.name.isEmpty
            ? L10n.s("contacts.thisContact")
            : selectedContact.name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.s("section.contacts"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        Task {
                            await loadContactItemsIfNeeded(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("contacts.reload"))
                    .disabled(isBusy || !isLoggedIn)

                    Button {
                        Task {
                            await createContact()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("contacts.add"))
                    .disabled(isBusy || !canSyncContacts)
                }

                if isBusy {
                    ProgressView(
                        isUploadingContacts
                            ? L10n.s("contacts.uploading")
                            : L10n.s("contacts.loading")
                    )
                    .controlSize(.small)
                }

                if let contactsErrorMessage {
                    Text(contactsErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if contactItems.isEmpty {
                    Text(L10n.s("contacts.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 2)
                } else {
                    List(sortedContactItems) { item in
                        Button {
                            selectContact(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    item.name.isEmpty
                                        ? L10n.s("contacts.noName") : item.name
                                )
                                .font(.headline)
                                if !item.email.isEmpty || !item.phone.isEmpty
                                    || !item.birthday.isEmpty
                                {
                                    HStack(spacing: 6) {
                                        if !item.email.isEmpty {
                                            Text(item.email)
                                        } else if !item.phone.isEmpty {
                                            Text(item.phone)
                                        }

                                        if !item.birthday.isEmpty {
                                            Image(systemName: "birthday.cake")
                                            Text(item.birthday)
                                        }
                                    }
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
                        .disabled(isBusy)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 280)

            Divider()

            ContactDetailView(
                contact: selectedContact,
                isBusy: isBusy,
                isEditing: isEditingSelection,
                nameDraft: $contactNameDraft,
                birthdayDraft: $contactBirthdayDraft,
                phoneDraft: $contactPhoneDraft,
                addressDraft: $contactAddressDraft,
                emailDraft: $contactEmailDraft,
                noteDraft: $contactNoteDraft,
                onToggleEdit: {
                    Task {
                        await toggleEditSelection()
                    }
                },
                onDelete: {
                    showDeleteConfirmation = true
                })
        }
        .alert(L10n.s("contacts.delete.title"), isPresented: $showDeleteConfirmation) {
            Button(L10n.s("common.cancel"), role: .cancel) {}
            Button(L10n.s("common.delete"), role: .destructive) {
                Task {
                    await deleteSelectedContact()
                }
            }
        } message: {
            Text(
                String(
                    format: L10n.s("contacts.delete.message.format"),
                    selectedContactDisplayName))
        }
        .task(id: syncContextID) {
            hasLoadedContacts = false
            clearContactSelection()
            await loadContactItemsIfNeeded(force: true)
        }
    }

    @MainActor
    private func loadContactItemsIfNeeded(force: Bool, preferredSelectedID: Int64? = nil) async {
        if isLoadingContacts {
            return
        }
        if hasLoadedContacts && !force {
            return
        }
        guard canSyncContacts,
            let token,
            let passwordManagerSalt
        else {
            contactsErrorMessage = L10n.s("contacts.error.setKey.load")
            contactItems = []
            hasLoadedContacts = false
            clearContactSelection()
            return
        }

        isLoadingContacts = true
        contactsErrorMessage = nil
        defer { isLoadingContacts = false }

        do {
            let items = try await service.loadContacts(
                token: token,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            contactItems = items.sorted(by: sortContactsByName)
            hasLoadedContacts = true
            updateSelectionAfterReload(preferredSelectedID: preferredSelectedID)
        } catch {
            contactsErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? L10n.s("contacts.error.load")
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
        guard canSyncContacts,
            let token,
            let passwordManagerSalt
        else {
            contactsErrorMessage = L10n.s("contacts.error.setKey.upload")
            return
        }

        isUploadingContacts = true
        contactsErrorMessage = nil
        defer { isUploadingContacts = false }

        do {
            try await service.saveContacts(
                token: token,
                contacts: contactItems,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
        } catch {
            contactsErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? L10n.s("contacts.error.upload")
        }
    }

    @MainActor
    private func createContact() async {
        guard canSyncContacts else {
            contactsErrorMessage = L10n.s("contacts.error.setKey.create")
            return
        }
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
        contactItems.sort(by: sortContactsByName)
        selectContact(newContact)
        await uploadAndReload(preferredSelectedID: newContact.id)
    }

    @MainActor
    private func toggleEditSelection() async {
        guard selectedContact != nil else {
            return
        }
        if isEditingSelection {
            await saveSelectedContactChanges()
        } else {
            isEditingSelection = true
        }
    }

    @MainActor
    private func saveSelectedContactChanges() async {
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
        isEditingSelection = false
        await uploadAndReload(preferredSelectedID: selectedContactID)
    }

    @MainActor
    private func deleteSelectedContact() async {
        guard let selectedContactID else {
            return
        }
        contactItems.removeAll { $0.id == selectedContactID }
        clearContactSelection()
        await uploadAndReload(preferredSelectedID: nil)
    }

    @MainActor
    private func uploadAndReload(preferredSelectedID: Int64?) async {
        await uploadContactItems()
        if contactsErrorMessage == nil {
            await loadContactItemsIfNeeded(force: true, preferredSelectedID: preferredSelectedID)
        }
    }

    private func selectContact(_ item: ContactItem) {
        selectedContactID = item.id
        contactNameDraft = item.name
        contactBirthdayDraft = item.birthday
        contactPhoneDraft = item.phone
        contactAddressDraft = item.address
        contactEmailDraft = item.email
        contactNoteDraft = item.note
        isEditingSelection = false
        contactsErrorMessage = nil
    }

    private func updateSelectionAfterReload(preferredSelectedID: Int64?) {
        let targetID = preferredSelectedID ?? selectedContactID
        guard let targetID,
            let selected = contactItems.first(where: { $0.id == targetID })
        else {
            if contactItems.isEmpty {
                clearContactSelection()
            }
            return
        }
        selectContact(selected)
    }

    private func clearContactSelection() {
        selectedContactID = nil
        isEditingSelection = false
        contactNameDraft = ""
        contactBirthdayDraft = ""
        contactPhoneDraft = ""
        contactAddressDraft = ""
        contactEmailDraft = ""
        contactNoteDraft = ""
    }

    private func sortContactsByName(_ lhs: ContactItem, _ rhs: ContactItem) -> Bool {
        let name1 = lhs.name.localizedLowercase
        let name2 = rhs.name.localizedLowercase
        if name1 == name2 {
            return lhs.id < rhs.id
        }
        return name1 < name2
    }
}

private struct ContactDetailView: View {
    let contact: ContactItem?
    let isBusy: Bool
    let isEditing: Bool
    @Binding var nameDraft: String
    @Binding var birthdayDraft: String
    @Binding var phoneDraft: String
    @Binding var addressDraft: String
    @Binding var emailDraft: String
    @Binding var noteDraft: String
    let onToggleEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(contactTitle)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: onToggleEdit) {
                    Image(systemName: isEditing ? "checkmark" : "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help(
                    isEditing
                        ? L10n.s("contacts.help.saveChanges")
                        : L10n.s("contacts.help.edit")
                )
                .disabled(contact == nil || isBusy)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help(L10n.s("contacts.delete"))
                .disabled(contact == nil || isBusy)
            }

            if contact == nil {
                Text(L10n.s("contacts.selectPrompt"))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Group {
                    if isEditing {
                        editableRow(label: L10n.s("contacts.field.name"), text: $nameDraft)
                    }
                    editableRow(
                        label: L10n.s("contacts.field.birthday"),
                        text: $birthdayDraft)
                    editableRow(label: L10n.s("contacts.field.phone"), text: $phoneDraft)
                    editableRow(label: L10n.s("contacts.field.email"), text: $emailDraft)
                    editableRow(
                        label: L10n.s("contacts.field.address"),
                        text: $addressDraft)
                    editableNoteRow(label: L10n.s("contacts.field.note"), text: $noteDraft)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contactTitle: String {
        guard let contact else {
            return L10n.s("contacts.contact")
        }
        return contact.name.isEmpty ? L10n.s("contacts.noName") : contact.name
    }

    @ViewBuilder
    private func editableRow(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEditing {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(readOnlyText(text.wrappedValue))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func editableNoteRow(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEditing {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 96)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(readOnlyText(text.wrappedValue))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private func readOnlyText(_ value: String) -> String {
        value.isEmpty ? L10n.s("common.notSet") : value
    }
}
