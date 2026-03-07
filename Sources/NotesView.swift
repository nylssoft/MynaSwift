import SwiftUI

struct NotesView: View {
    let service: Servicing
    let authentication: AuthenticationResponse?
    let passwordManagerSalt: String?
    let dataProtectionSecurityKey: String
    let isLoggedIn: Bool

    @State private var notes: [Note] = []
    @State private var hasLoadedNotes = false
    @State private var notesErrorMessage: String?

    @State private var isLoadingNotes = false
    @State private var isLoadingSelectedNote = false
    @State private var isCreatingNote = false
    @State private var isSavingNote = false
    @State private var isDeletingNote = false

    @State private var selectedNoteID: Int64?
    @State private var isEditingSelection = false
    @State private var noteTitleDraft = ""
    @State private var noteContentDraft = ""

    @State private var showDeleteConfirmation = false

    private var token: String? {
        authentication?.token
    }

    private var canManageNotes: Bool {
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
        isLoadingNotes || isLoadingSelectedNote || isCreatingNote || isSavingNote || isDeletingNote
    }

    private var isListBusy: Bool {
        isLoadingNotes || isCreatingNote || isSavingNote || isDeletingNote
    }

    private var syncContextID: String {
        "\(isLoggedIn)|\(token ?? "")"
    }

    private var selectedNote: Note? {
        guard let selectedNoteID else {
            return nil
        }
        return notes.first { $0.id == selectedNoteID }
    }

    private var sortedNotes: [Note] {
        notes.sorted(by: sortNotes)
    }

    private var selectedNoteDisplayName: String {
        guard let selectedNote else {
            return L10n.s("notes.thisNote")
        }
        return selectedNote.title.isEmpty ? L10n.s("notes.thisNote") : selectedNote.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.s("section.notes"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        Task {
                            await loadNotes(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("notes.reload"))
                    .disabled(isListBusy || !isLoggedIn)

                    Button {
                        Task {
                            await createNote()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("notes.add"))
                    .disabled(isListBusy || !canManageNotes)
                }

                if isListBusy {
                    ProgressView(busyText)
                        .controlSize(.small)
                }

                if let notesErrorMessage {
                    Text(notesErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if notes.isEmpty {
                    Text(L10n.s("notes.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 2)
                } else {
                    List(sortedNotes) { item in
                        Button {
                            Task {
                                await selectNote(item)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title.isEmpty ? L10n.s("notes.noTitle") : item.title)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedNoteID == item.id ? Color.primary.opacity(0.12) : Color.clear
                        )
                        .disabled(isListBusy)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300)

            Divider()

            NoteDetailView(
                note: selectedNote,
                isBusy: isBusy,
                isLoadingDetails: isLoadingSelectedNote,
                isEditing: isEditingSelection,
                titleDraft: $noteTitleDraft,
                contentDraft: $noteContentDraft,
                onToggleEdit: {
                    Task {
                        await toggleEditSelection()
                    }
                },
                onDelete: {
                    showDeleteConfirmation = true
                })
        }
        .alert(L10n.s("notes.delete.title"), isPresented: $showDeleteConfirmation) {
            Button(L10n.s("common.cancel"), role: .cancel) {}
            Button(L10n.s("common.delete"), role: .destructive) {
                Task {
                    await deleteSelectedNote()
                }
            }
        } message: {
            Text(
                String(
                    format: L10n.s("notes.delete.message.format"),
                    selectedNoteDisplayName))
        }
        .task(id: syncContextID) {
            hasLoadedNotes = false
            clearSelection()
            await loadNotes(force: true)
        }
    }

    private var busyText: String {
        if isCreatingNote {
            return L10n.s("notes.creating")
        }
        if isSavingNote {
            return L10n.s("notes.saving")
        }
        if isDeletingNote {
            return L10n.s("notes.deleting")
        }
        return L10n.s("notes.loading")
    }

    @MainActor
    private func loadNotes(force: Bool, preferredSelectedID: Int64? = nil) async {
        if isLoadingNotes {
            return
        }
        if hasLoadedNotes && !force {
            return
        }
        guard canManageNotes,
            let token,
            let passwordManagerSalt
        else {
            notesErrorMessage =
                isLoggedIn ? L10n.s("notes.error.setKey") : L10n.s("notes.error.loginRequired")
            notes = []
            hasLoadedNotes = false
            clearSelection()
            return
        }

        isLoadingNotes = true
        notesErrorMessage = nil
        defer { isLoadingNotes = false }

        do {
            notes = try await service.getNotes(
                token: token,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            hasLoadedNotes = true
            updateSelectionAfterReload(preferredSelectedID: preferredSelectedID)
        } catch {
            notesErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("notes.error.load")
            notes = []
            hasLoadedNotes = false
            clearSelection()
        }
    }

    @MainActor
    private func selectNote(_ note: Note) async {
        if selectedNoteID == note.id {
            return
        }
        selectedNoteID = note.id
        noteTitleDraft = note.title
        noteContentDraft = note.content ?? ""
        isEditingSelection = false
        notesErrorMessage = nil
        await loadSelectedNoteDetails(noteID: note.id)
    }

    @MainActor
    private func loadSelectedNoteDetails(noteID: Int64) async {
        guard canManageNotes, let token else {
            return
        }
        if isLoadingSelectedNote {
            return
        }

        isLoadingSelectedNote = true
        defer { isLoadingSelectedNote = false }

        do {
            guard let passwordManagerSalt else {
                notesErrorMessage = L10n.s("notes.error.setKey")
                return
            }
            let note = try await service.getNote(
                token: token,
                id: noteID,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
            }
            if selectedNoteID == note.id {
                noteTitleDraft = note.title
                noteContentDraft = note.content ?? ""
            }
        } catch {
            notesErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("notes.error.details")
        }
    }

    @MainActor
    private func createNote() async {
        guard canManageNotes, let token else {
            notesErrorMessage = L10n.s("notes.error.setKey")
            return
        }
        if isCreatingNote {
            return
        }

        isCreatingNote = true
        notesErrorMessage = nil
        defer { isCreatingNote = false }

        do {
            guard let passwordManagerSalt else {
                notesErrorMessage = L10n.s("notes.error.setKey")
                return
            }
            let id = try await service.createNewNote(
                token: token,
                title: L10n.s("notes.newTitle"),
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            await loadNotes(force: true, preferredSelectedID: id)
            if let selected = notes.first(where: { $0.id == id }) {
                await selectNote(selected)
            }
            isEditingSelection = true
        } catch {
            notesErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("notes.error.create")
        }
    }

    @MainActor
    private func toggleEditSelection() async {
        guard selectedNote != nil else {
            return
        }
        if isEditingSelection {
            await saveSelectedNote()
        } else {
            isEditingSelection = true
        }
    }

    @MainActor
    private func saveSelectedNote() async {
        guard let selectedNoteID,
            canManageNotes,
            let token
        else {
            return
        }
        if isSavingNote {
            return
        }

        isSavingNote = true
        notesErrorMessage = nil
        defer { isSavingNote = false }

        do {
            guard let passwordManagerSalt else {
                notesErrorMessage = L10n.s("notes.error.setKey")
                return
            }
            _ = try await service.updateNote(
                token: token,
                id: selectedNoteID,
                title: noteTitleDraft,
                content: noteContentDraft,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            if let index = notes.firstIndex(where: { $0.id == selectedNoteID }) {
                notes[index].title = noteTitleDraft
                notes[index].content = noteContentDraft
            }
            isEditingSelection = false
            notes.sort(by: sortNotes)
            await loadSelectedNoteDetails(noteID: selectedNoteID)
        } catch {
            notesErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("notes.error.save")
        }
    }

    @MainActor
    private func deleteSelectedNote() async {
        guard let selectedNoteID,
            canManageNotes,
            let token
        else {
            return
        }
        if isDeletingNote {
            return
        }

        isDeletingNote = true
        notesErrorMessage = nil
        defer { isDeletingNote = false }

        do {
            try await service.deleteNote(token: token, id: selectedNoteID)
            notes.removeAll { $0.id == selectedNoteID }
            clearSelection()
        } catch {
            notesErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("notes.error.delete")
        }
    }

    private func updateSelectionAfterReload(preferredSelectedID: Int64?) {
        let targetID = preferredSelectedID ?? selectedNoteID
        guard let targetID,
            let selected = notes.first(where: { $0.id == targetID })
        else {
            if notes.isEmpty {
                clearSelection()
            }
            return
        }
        selectedNoteID = selected.id
        noteTitleDraft = selected.title
        noteContentDraft = selected.content ?? ""
    }

    private func clearSelection() {
        selectedNoteID = nil
        isEditingSelection = false
        noteTitleDraft = ""
        noteContentDraft = ""
    }

    private func sortNotes(_ lhs: Note, _ rhs: Note) -> Bool {
        let lhsTitle = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let rhsTitle = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        if lhsTitle == rhsTitle {
            return lhs.id < rhs.id
        }
        return lhsTitle < rhsTitle
    }
}

private struct NoteDetailView: View {
    let note: Note?
    let isBusy: Bool
    let isLoadingDetails: Bool
    let isEditing: Bool
    @Binding var titleDraft: String
    @Binding var contentDraft: String
    let onToggleEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(noteTitle)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: onToggleEdit) {
                    Image(systemName: isEditing ? "checkmark" : "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help(isEditing ? L10n.s("notes.help.saveChanges") : L10n.s("notes.help.edit"))
                .disabled(note == nil || isBusy)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help(L10n.s("notes.delete"))
                .disabled(note == nil || isBusy)
            }

            if note == nil {
                Text(L10n.s("notes.selectPrompt"))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                if isLoadingDetails {
                    ProgressView(L10n.s("notes.loadingDetails"))
                        .controlSize(.small)
                }

                if let lastModifiedText {
                    Text(String(format: L10n.s("notes.lastModified.format"), lastModifiedText))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isEditing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("notes.field.title"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(L10n.s("notes.field.title"), text: $titleDraft)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.s("notes.field.content"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isEditing {
                        TextEditor(text: $contentDraft)
                            .font(.body)
                            .frame(minHeight: 180)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Text(readOnlyText(contentDraft))
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var noteTitle: String {
        guard let note else {
            return L10n.s("notes.note")
        }
        return note.title.isEmpty ? L10n.s("notes.noTitle") : note.title
    }

    private var lastModifiedText: String? {
        guard let value = note?.lastModifiedUtc,
            !value.isEmpty
        else {
            return nil
        }
        return DateFormattingUtility.displayDate(fromUnixOrISO: value)
    }

    private func readOnlyText(_ value: String) -> String {
        value.isEmpty ? L10n.s("common.notSet") : value
    }
}
