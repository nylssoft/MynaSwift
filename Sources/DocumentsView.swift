import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {
    private enum DocumentType: String {
        case volume = "Volume"
        case folder = "Folder"
        case document = "Document"
    }

    private static let maxUploadBytes = 20 * 1024 * 1024
    private static let appDownloadDirectoryName = "MynaSwift"

    private enum ExistingDownloadChoice {
        case overwrite
        case openExisting
        case cancel
    }

    let service: Servicing
    let authentication: AuthenticationResponse?
    let userInfo: UserInfoResponse?
    let dataProtectionSecurityKey: String
    let isLoggedIn: Bool
    let onActivityStatusChange: (String?) -> Void
    let onStatusMessage: (String) -> Void

    @State private var visibleItems: [DocumentItem] = []
    @State private var currentDocumentItem: DocumentItem?
    @State private var selectedItemID: Int64?
    @State private var selectedItemIDs: Set<Int64> = []
    @State private var isLoadingItems = false
    @State private var isDownloadingDocument = false
    @State private var isCreatingFolder = false
    @State private var isUploadingDocument = false
    @State private var isRenamingItem = false
    @State private var isDeletingItems = false
    @State private var isMovingItems = false
    @State private var hasLoadedItems = false
    @State private var documentsErrorMessage: String?
    @State private var showCreateFolderSheet = false
    @State private var showRenameItemSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showMoveSheet = false
    @State private var folderNameDraft = ""
    @State private var renameNameDraft = ""
    @State private var renameTargetID: Int64?
    @State private var thumbnailImage: NSImage?
    @State private var isLoadingThumbnail = false

    private var token: String? {
        authentication?.token
    }

    private var passwordManagerSalt: String? {
        userInfo?.passwordManagerSalt
    }

    private var canBrowseDocuments: Bool {
        guard isLoggedIn,
            let token,
            !token.isEmpty
        else {
            return false
        }
        return true
    }

    private var canDownloadDocuments: Bool {
        guard canBrowseDocuments,
            let passwordManagerSalt,
            !passwordManagerSalt.isEmpty,
            !dataProtectionSecurityKey.isEmpty
        else {
            return false
        }
        return true
    }

    private var canModifyDocuments: Bool {
        canBrowseDocuments
    }

    private var canUploadDocuments: Bool {
        canDownloadDocuments
    }

    private var isBusy: Bool {
        isLoadingItems || isDownloadingDocument || isCreatingFolder || isUploadingDocument
            || isRenamingItem || isDeletingItems || isMovingItems
    }

    private var hasBulkSelection: Bool {
        !selectedItemIDs.isEmpty
    }

    private var areAllVisibleItemsSelected: Bool {
        !visibleItems.isEmpty && visibleItems.allSatisfy { selectedItemIDs.contains($0.id) }
    }

    private var selectAllToggleKey: String {
        areAllVisibleItemsSelected ? "documents.deselectAll" : "documents.selectAll"
    }

    private var canRenameBulkSelection: Bool {
        selectedItemIDs.count == 1
    }

    private var syncContextID: String {
        "\(isLoggedIn)|\(token ?? "")|\(passwordManagerSalt ?? "")"
    }

    private var thumbnailContextID: String {
        "\(selectedItemID ?? -1)|\(selectedItem?.name ?? "")"
    }

    private var canNavigateUp: Bool {
        currentDocumentItem?.parentID != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.s("section.documents"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        Task {
                            await uploadNewDocument()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.upload"))
                    .disabled(isBusy || !canUploadDocuments || currentDocumentItem == nil)

                    Button {
                        folderNameDraft = ""
                        showCreateFolderSheet = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.newFolder"))
                    .disabled(isBusy || !canModifyDocuments || currentDocumentItem == nil)

                    Button {
                        showMoveSheet = true
                    } label: {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.moveSelected"))
                    .disabled(isBusy || !canModifyDocuments || !hasBulkSelection)

                    Button {
                        openRenameSheetForBulkSelection()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.rename"))
                    .disabled(isBusy || !canModifyDocuments || !canRenameBulkSelection)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.deleteSelected"))
                    .disabled(isBusy || !canModifyDocuments || !hasBulkSelection)

                    Button {
                        Task {
                            await loadDocumentItems(force: true, currentID: currentDocumentItem?.id)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.reload"))
                    .disabled(isBusy || !canBrowseDocuments)
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await loadDocumentItems(force: true, currentID: nil)
                        }
                    } label: {
                        Image(systemName: "house")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.home"))
                    .disabled(isBusy || !canBrowseDocuments)

                    Button {
                        Task {
                            await loadDocumentItems(force: true, currentID: currentDocumentItem?.parentID)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("documents.up"))
                    .disabled(isBusy || !canBrowseDocuments || !canNavigateUp)

                    if let currentDocumentItem {
                        Text(currentDocumentItem.name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let documentsErrorMessage {
                    Text(documentsErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if visibleItems.isEmpty {
                    Text(L10n.s("documents.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 2)
                } else {
                    List {
                        HStack(spacing: 8) {
                            Button {
                                toggleSelectAllVisibleItems()
                            } label: {
                                Image(systemName: areAllVisibleItemsSelected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(
                                        areAllVisibleItemsSelected
                                            ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.s(selectAllToggleKey))
                            .disabled(isBusy || visibleItems.isEmpty)

                            Text(L10n.s(selectAllToggleKey))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }

                        ForEach(visibleItems) { item in
                            HStack(spacing: 8) {
                                Button {
                                    toggleBulkSelection(for: item.id)
                                } label: {
                                    Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(
                                            selectedItemIDs.contains(item.id)
                                                ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("documents.selectItem"))
                                .disabled(isBusy)

                                Button {
                                    Task {
                                        await processItem(item)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: symbolName(for: item.type, fileName: item.name))
                                            .frame(width: 18)
                                            .foregroundStyle(item.type == DocumentType.folder.rawValue ? .yellow : .secondary)
                                        Text(item.name)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        if item.type == DocumentType.document.rawValue {
                                            Text(formattedFileSize(item.size))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .disabled(isBusy)
                            }
                            .listRowBackground(selectedItemID == item.id ? Color.primary.opacity(0.12) : Color.clear)
                        }
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 420)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.s("documents.detail.title"))
                    .font(.title3)
                    .fontWeight(.semibold)

                if let selected = selectedItem {
                    if selected.type == DocumentType.document.rawValue {
                        DocumentThumbnailView(
                            thumbnailImage: thumbnailImage,
                            isLoading: isLoadingThumbnail,
                            fallbackSymbolName: documentSymbolName(for: selected.name))
                    }

                    HStack {
                        Text(selected.name)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            renameTargetID = selected.id
                            renameNameDraft = selected.name
                            showRenameItemSheet = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.s("documents.rename"))
                        .disabled(isBusy || !canModifyDocuments)
                    }

                    DetailRow(label: L10n.s("documents.field.name"), value: selected.name)
                    DetailRow(label: L10n.s("documents.field.type"), value: selected.type)
                    if selected.type == DocumentType.document.rawValue {
                        DetailRow(label: L10n.s("documents.field.size"), value: formattedFileSize(selected.size))
                        if let localFileURL = resolveDownloadedFileURL(for: selected) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(L10n.s("documents.field.localFile"))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 110, alignment: .leading)
                                Text(localFileURL.path)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                Button {
                                    revealInFinder(localFileURL)
                                    onStatusMessage(
                                        String(
                                            format: L10n.s("documents.status.revealedInFinder.format"),
                                            localFileURL.lastPathComponent))
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("documents.showInFinder"))
                                Spacer(minLength: 0)
                            }
                        }
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await downloadDocument(selected)
                                }
                            } label: {
                                Label(L10n.s("documents.download"), systemImage: "arrow.down.circle")
                            }
                            .disabled(isBusy)

                            Button {
                                Task {
                                    await replaceDocument(selected)
                                }
                            } label: {
                                Label(L10n.s("documents.replace"), systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(isBusy || !canUploadDocuments)
                        }
                    }
                    Spacer(minLength: 0)
                } else {
                    Text(L10n.s("documents.selectPrompt"))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .sheet(isPresented: $showCreateFolderSheet) {
            DocumentNameSheet(
                title: L10n.s("documents.newFolder.title"),
                fieldLabel: L10n.s("documents.newFolder.name"),
                actionTitle: L10n.s("documents.newFolder.create"),
                name: $folderNameDraft,
                isPresented: $showCreateFolderSheet,
                onSubmit: {
                    Task {
                        await createFolder()
                    }
                })
        }
        .sheet(isPresented: $showRenameItemSheet) {
            DocumentNameSheet(
                title: L10n.s("documents.rename.title"),
                fieldLabel: L10n.s("documents.rename.name"),
                actionTitle: L10n.s("documents.rename.save"),
                name: $renameNameDraft,
                isPresented: $showRenameItemSheet,
                onSubmit: {
                    Task {
                        await renameSelectedItem()
                    }
                })
        }
        .sheet(isPresented: $showMoveSheet) {
            DocumentMoveSheet(
                service: service,
                token: token,
                initialFolderID: currentDocumentItem?.id,
                onMove: { destinationID in
                    Task {
                        await moveSelectedItems(to: destinationID)
                    }
                })
        }
        .alert(L10n.s("documents.deleteSelected.title"), isPresented: $showDeleteConfirmation) {
            Button(L10n.s("common.cancel"), role: .cancel) {}
            Button(L10n.s("common.delete"), role: .destructive) {
                Task {
                    await deleteSelectedItems()
                }
            }
        } message: {
            Text(
                String(
                    format: L10n.s("documents.deleteSelected.message.format"),
                    selectedItemIDs.count))
        }
        .task(id: syncContextID) {
            hasLoadedItems = false
            clearSelection()
            await loadDocumentItems(force: true, currentID: nil)
        }
        .task(id: thumbnailContextID) {
            await refreshThumbnailForSelection()
        }
    }

    private var selectedItem: DocumentItem? {
        guard let selectedItemID else {
            return nil
        }
        return visibleItems.first { $0.id == selectedItemID }
    }

    @MainActor
    private func loadDocumentItems(force: Bool, currentID: Int64?, preferredSelectedID: Int64? = nil)
        async
    {
        if isLoadingItems {
            return
        }
        if hasLoadedItems && !force {
            return
        }
        guard canBrowseDocuments,
            let token
        else {
            documentsErrorMessage = L10n.s("documents.error.loginRequired")
            visibleItems = []
            clearSelection()
            return
        }

        isLoadingItems = true
        onActivityStatusChange(L10n.s("documents.loading"))
        documentsErrorMessage = nil
        defer {
            isLoadingItems = false
            onActivityStatusChange(nil)
        }

        do {
            let items = try await service.getDocumentItems(token: token, currentID: currentID)
            guard let volume = items.first(where: { $0.type == DocumentType.volume.rawValue }) else {
                visibleItems = []
                currentDocumentItem = nil
                documentsErrorMessage = L10n.s("documents.error.load")
                return
            }

            let resolvedCurrent: DocumentItem
            if let currentID,
                let current = items.first(where: { $0.id == currentID })
            {
                resolvedCurrent = current
            } else {
                resolvedCurrent = volume
            }

            let activeID = resolvedCurrent.id
            let folders = items
                .filter {
                    $0.type == DocumentType.folder.rawValue
                        && $0.parentID == activeID
                        && $0.accessRole == nil
                }
                .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }

            let documents = items
                .filter {
                    $0.type == DocumentType.document.rawValue
                        && $0.accessRole == nil
                }
                .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }

            currentDocumentItem = resolvedCurrent
            visibleItems = folders + documents
            hasLoadedItems = true
            selectedItemIDs = selectedItemIDs.intersection(Set(visibleItems.map(\.id)))
            if let preferredSelectedID,
                visibleItems.contains(where: { $0.id == preferredSelectedID })
            {
                selectedItemID = preferredSelectedID
            } else {
                clearSelection()
            }
        } catch {
            documentsErrorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.load")
            visibleItems = []
            currentDocumentItem = nil
            clearSelection()
            hasLoadedItems = false
        }
    }

    @MainActor
    private func processItem(_ item: DocumentItem) async {
        selectedItemID = item.id
        switch item.type {
        case DocumentType.folder.rawValue:
            hasLoadedItems = false
            await loadDocumentItems(force: true, currentID: item.id, preferredSelectedID: nil)
        case DocumentType.volume.rawValue:
            hasLoadedItems = false
            await loadDocumentItems(force: true, currentID: nil, preferredSelectedID: nil)
        case DocumentType.document.rawValue:
            // Select documents in the list, but do not start a download automatically.
            break
        default:
            break
        }
    }

    @MainActor
    private func createFolder() async {
        let folderName = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty else {
            documentsErrorMessage = L10n.s("documents.error.invalidName")
            return
        }
        guard canModifyDocuments,
            let token,
            let parentID = currentDocumentItem?.id
        else {
            documentsErrorMessage = L10n.s("documents.error.loginRequired")
            return
        }
        if isCreatingFolder {
            return
        }

        isCreatingFolder = true
        onActivityStatusChange(L10n.s("documents.creatingFolder"))
        documentsErrorMessage = nil
        defer {
            isCreatingFolder = false
            onActivityStatusChange(nil)
        }

        do {
            _ = try await service.createDocumentFolder(
                token: token,
                parentID: parentID,
                name: folderName)
            showCreateFolderSheet = false
            folderNameDraft = ""
            hasLoadedItems = false
            await loadDocumentItems(force: true, currentID: parentID)
            onStatusMessage(String(format: L10n.s("documents.status.folderCreated.format"), folderName))
        } catch {
            documentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.createFolder")
        }
    }

    @MainActor
    private func renameSelectedItem() async {
        let fallbackSelectedID = selectedItemIDs.count == 1 ? selectedItemIDs.first : nil
        let targetID = renameTargetID ?? selectedItem?.id ?? fallbackSelectedID
        guard let targetID,
            let current = visibleItems.first(where: { $0.id == targetID })
        else {
            return
        }
        let newName = renameNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            documentsErrorMessage = L10n.s("documents.error.invalidName")
            return
        }
        guard canModifyDocuments,
            let token
        else {
            documentsErrorMessage = L10n.s("documents.error.loginRequired")
            return
        }
        if isRenamingItem {
            return
        }

        isRenamingItem = true
        onActivityStatusChange(L10n.s("documents.renaming"))
        documentsErrorMessage = nil
        defer {
            isRenamingItem = false
            onActivityStatusChange(nil)
        }

        do {
            try await service.renameDocumentItem(token: token, id: targetID, name: newName)
            showRenameItemSheet = false
            renameTargetID = nil
            hasLoadedItems = false
            await loadDocumentItems(
                force: true,
                currentID: currentDocumentItem?.id,
                preferredSelectedID: current.id)
            onStatusMessage(String(format: L10n.s("documents.status.renamed.format"), newName))
        } catch {
            documentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.rename")
        }
    }

    private func openRenameSheetForBulkSelection() {
        guard selectedItemIDs.count == 1,
            let id = selectedItemIDs.first,
            let item = visibleItems.first(where: { $0.id == id })
        else {
            return
        }
        renameTargetID = id
        renameNameDraft = item.name
        showRenameItemSheet = true
    }

    @MainActor
    private func uploadNewDocument() async {
        guard let parentID = currentDocumentItem?.id else {
            return
        }
        guard let sourceURL = promptSourceFileURL() else {
            return
        }
        await uploadDocumentFile(
            sourceURL: sourceURL,
            parentID: parentID,
            targetFileName: nil,
            overwrite: false,
            successMessageKey: "documents.status.uploaded.format",
            preferredSelectedID: nil)
    }

    @MainActor
    private func replaceDocument(_ item: DocumentItem) async {
        guard item.type == DocumentType.document.rawValue,
            let parentID = currentDocumentItem?.id
        else {
            return
        }
        guard let sourceURL = promptSourceFileURL() else {
            return
        }
        await uploadDocumentFile(
            sourceURL: sourceURL,
            parentID: parentID,
            targetFileName: item.name,
            overwrite: true,
            successMessageKey: "documents.status.replaced.format",
            preferredSelectedID: item.id)
    }

    @MainActor
    private func uploadDocumentFile(
        sourceURL: URL,
        parentID: Int64,
        targetFileName: String?,
        overwrite: Bool,
        successMessageKey: String,
        preferredSelectedID: Int64?
    ) async {
        guard canUploadDocuments,
            let token,
            let passwordManagerSalt
        else {
            documentsErrorMessage = L10n.s("documents.error.setKey.upload")
            return
        }
        if isUploadingDocument {
            return
        }

        isUploadingDocument = true
        onActivityStatusChange(L10n.s("documents.uploading"))
        documentsErrorMessage = nil
        defer {
            isUploadingDocument = false
            onActivityStatusChange(nil)
        }

        do {
            let fileData = try Data(contentsOf: sourceURL)
            if fileData.count > Self.maxUploadBytes {
                documentsErrorMessage = String(
                    format: L10n.s("documents.error.fileTooLarge.format"),
                    sourceURL.lastPathComponent,
                    formattedFileSize(Int64(fileData.count)))
                return
            }

            let fileName = targetFileName ?? sourceURL.lastPathComponent
            try await service.uploadDocument(
                token: token,
                parentID: parentID,
                fileName: fileName,
                fileData: fileData,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt,
                overwrite: overwrite)

            hasLoadedItems = false
            await loadDocumentItems(
                force: true,
                currentID: parentID,
                preferredSelectedID: preferredSelectedID)
            onStatusMessage(String(format: L10n.s(successMessageKey), fileName))
        } catch {
            documentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.upload")
        }
    }

    @MainActor
    private func downloadDocument(_ item: DocumentItem) async {
        guard item.type == DocumentType.document.rawValue else {
            return
        }
        guard canDownloadDocuments,
            let token,
            let passwordManagerSalt
        else {
            documentsErrorMessage = L10n.s("documents.error.setKey.download")
            return
        }
        if isDownloadingDocument {
            return
        }

        isDownloadingDocument = true
        onActivityStatusChange(L10n.s("documents.downloading"))
        documentsErrorMessage = nil
        defer {
            isDownloadingDocument = false
            onActivityStatusChange(nil)
        }

        do {
            let destinationURL = try ensureAppDownloadDirectory().appendingPathComponent(
                localDownloadFileName(for: item))
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                switch promptForExistingDownload(at: destinationURL) {
                case .overwrite:
                    break
                case .openExisting:
                    openDocument(destinationURL)
                    return
                case .cancel:
                    return
                }
            }

            let fileData = try await service.downloadDocument(
                token: token,
                id: item.id,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            try fileData.write(to: destinationURL, options: .atomic)

            _ = guessedMimeType(for: item.name)
            openDocument(destinationURL)

            onStatusMessage(
                String(
                    format: L10n.s("documents.status.downloadLocation.format"),
                    destinationURL.lastPathComponent,
                    destinationURL.path))
        } catch {
            documentsErrorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.download")
        }
    }

    private func ensureAppDownloadDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard
            let downloadsDirectory = DownloadDirectoryAccessManager.shared
                .accessibleDownloadsDirectoryURL(promptIfNeeded: true)
        else {
            throw NSError(
                domain: "MynaSwift",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: L10n.s("documents.error.downloadDirectoryPermission")
                ])
        }
        let appDownloadsDirectory = downloadsDirectory.appendingPathComponent(
            Self.appDownloadDirectoryName,
            isDirectory: true)

        if !fileManager.fileExists(atPath: appDownloadsDirectory.path) {
            try fileManager.createDirectory(
                at: appDownloadsDirectory,
                withIntermediateDirectories: true)
        }
        return appDownloadsDirectory
    }

    private func localDownloadFileName(for item: DocumentItem) -> String {
        let originalName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "document"
        let resolvedName = originalName.isEmpty ? fallbackName : originalName

        let ext = URL(fileURLWithPath: resolvedName).pathExtension
        let baseName: String
        if ext.isEmpty {
            baseName = resolvedName
        } else {
            baseName = String(resolvedName.dropLast(ext.count + 1))
        }
        let safeBaseName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseName = safeBaseName.isEmpty ? fallbackName : safeBaseName

        if ext.isEmpty {
            return "\(resolvedBaseName)-\(item.id)"
        }
        return "\(resolvedBaseName)-\(item.id).\(ext)"
    }

    private func promptForExistingDownload(at fileURL: URL) -> ExistingDownloadChoice {
        let alert = NSAlert()
        alert.messageText = L10n.s("documents.downloadExists.title")
        alert.informativeText = String(
            format: L10n.s("documents.downloadExists.message.format"),
            fileURL.lastPathComponent)
        alert.addButton(withTitle: L10n.s("documents.downloadExists.overwrite"))
        alert.addButton(withTitle: L10n.s("documents.downloadExists.openExisting"))
        alert.addButton(withTitle: L10n.s("common.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .overwrite
        case .alertSecondButtonReturn:
            return .openExisting
        default:
            return .cancel
        }
    }

    private func revealInFinder(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func promptSourceFileURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.s("documents.openPanel.title")
        panel.prompt = L10n.s("documents.openPanel.prompt")
        let response = panel.runModal()
        guard response == .OK else {
            return nil
        }
        return panel.url
    }

    private func symbolName(for type: String, fileName: String? = nil) -> String {
        switch type {
        case DocumentType.folder.rawValue:
            return "folder"
        case DocumentType.volume.rawValue:
            return "externaldrive"
        case DocumentType.document.rawValue:
            return documentSymbolName(for: fileName ?? "")
        default:
            return "questionmark.folder"
        }
    }

    private func documentSymbolName(for fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.richtext"
        case "txt", "md", "rtf":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "bmp", "webp", "tif", "tiff", "heic", "svg":
            return "photo"
        case "zip", "7z", "rar", "tar", "gz", "bz", "bz2":
            return "doc.zipper"
        case "mp3", "wav", "aac", "m4a", "flac", "ogg":
            return "music.note"
        case "mp4", "mov", "avi", "mkv", "webm", "mpeg", "mpg":
            return "film"
        case "xls", "xlsx", "csv":
            return "tablecells"
        case "ppt", "pptx", "key":
            return "chart.bar.doc.horizontal"
        case "doc", "docx", "odt":
            return "doc.plaintext"
        case "json", "xml", "yml", "yaml", "js", "ts", "swift", "py", "java", "c", "cpp", "h", "hpp", "css", "html":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }

    private func formattedFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func guessedMimeType(for fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard !ext.isEmpty else {
            return "application/octet-stream"
        }
        if let type = UTType(filenameExtension: ext),
            let mimeType = type.preferredMIMEType
        {
            return mimeType
        }
        return fallbackMimeType(forExtension: ext)
    }

    private func fallbackMimeType(forExtension ext: String) -> String {
        let map: [String: String] = [
            "txt": "text/plain",
            "pdf": "application/pdf",
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "csv": "text/csv",
            "json": "application/json",
            "xml": "application/xml",
            "zip": "application/zip"
        ]
        return map[ext] ?? "application/octet-stream"
    }

    private func openDocument(_ fileURL: URL) {
        let opened = NSWorkspace.shared.open(fileURL)
        if opened {
            onStatusMessage(
                String(
                    format: L10n.s("documents.status.opened.format"),
                    fileURL.lastPathComponent))
        } else {
            documentsErrorMessage = L10n.s("documents.error.open")
        }
    }

    @MainActor
    private func refreshThumbnailForSelection() async {
        guard let selected = selectedItem,
            selected.type == DocumentType.document.rawValue
        else {
            thumbnailImage = nil
            isLoadingThumbnail = false
            return
        }

        guard let localFileURL = resolveDownloadedFileURL(for: selected) else {
            thumbnailImage = nil
            isLoadingThumbnail = false
            return
        }

        isLoadingThumbnail = true
        defer {
            isLoadingThumbnail = false
        }

        if let thumbnail = await generateThumbnail(for: localFileURL, maxSize: CGSize(width: 240, height: 180)) {
            thumbnailImage = thumbnail
        } else {
            thumbnailImage = NSWorkspace.shared.icon(forFile: localFileURL.path)
        }
    }

    private func generateThumbnail(for fileURL: URL, maxSize: CGSize) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: maxSize,
            scale: scale,
            representationTypes: .all)

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                representation,
                _ in
                guard let cgImage = representation?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: NSImage(cgImage: cgImage, size: maxSize))
            }
        }
    }

    private func resolveDownloadedFileURL(for item: DocumentItem) -> URL? {
        let fileManager = FileManager.default
        guard let downloadsDirectory = try? ensureAppDownloadDirectory() else {
            return nil
        }
        let fileURL = downloadsDirectory.appendingPathComponent(localDownloadFileName(for: item))
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private func clearSelection() {
        selectedItemID = nil
        selectedItemIDs.removeAll()
    }

    private func toggleBulkSelection(for id: Int64) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func toggleSelectAllVisibleItems() {
        guard !visibleItems.isEmpty else {
            return
        }
        if areAllVisibleItemsSelected {
            visibleItems.forEach { selectedItemIDs.remove($0.id) }
        } else {
            visibleItems.forEach { selectedItemIDs.insert($0.id) }
        }
    }

    @MainActor
    private func deleteSelectedItems() async {
        guard canModifyDocuments,
            let token,
            let parentID = currentDocumentItem?.id
        else {
            documentsErrorMessage = L10n.s("documents.error.loginRequired")
            return
        }
        let ids = Array(selectedItemIDs)
        guard !ids.isEmpty else {
            return
        }
        if isDeletingItems {
            return
        }

        isDeletingItems = true
        onActivityStatusChange(L10n.s("documents.deleting"))
        documentsErrorMessage = nil
        defer {
            isDeletingItems = false
            onActivityStatusChange(nil)
        }

        do {
            try await service.deleteDocumentItems(token: token, parentID: parentID, ids: ids)
            selectedItemIDs.removeAll()
            hasLoadedItems = false
            await loadDocumentItems(force: true, currentID: parentID)
            onStatusMessage(String(format: L10n.s("documents.status.deleted.format"), ids.count))
        } catch {
            documentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.delete")
        }
    }

    @MainActor
    private func moveSelectedItems(to destinationID: Int64) async {
        guard canModifyDocuments,
            let token
        else {
            documentsErrorMessage = L10n.s("documents.error.loginRequired")
            return
        }
        let ids = Array(selectedItemIDs)
        guard !ids.isEmpty else {
            return
        }
        if isMovingItems {
            return
        }

        isMovingItems = true
        onActivityStatusChange(L10n.s("documents.moving"))
        documentsErrorMessage = nil
        defer {
            isMovingItems = false
            onActivityStatusChange(nil)
        }

        do {
            try await service.moveDocumentItems(token: token, parentID: destinationID, ids: ids)
            showMoveSheet = false
            selectedItemIDs.removeAll()
            hasLoadedItems = false
            await loadDocumentItems(force: true, currentID: currentDocumentItem?.id)
            onStatusMessage(String(format: L10n.s("documents.status.moved.format"), ids.count))
        } catch {
            documentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.move")
        }
    }
}

private struct DocumentThumbnailView: View {
    let thumbnailImage: NSImage?
    let isLoading: Bool
    let fallbackSymbolName: String

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            } else if let thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: fallbackSymbolName)
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(L10n.s("documents.preview.unavailable"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DocumentMoveSheet: View {
    private enum DocumentType: String {
        case volume = "Volume"
        case folder = "Folder"
    }

    let service: Servicing
    let token: String?
    let initialFolderID: Int64?
    let onMove: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentFolderID: Int64?
    @State private var currentFolder: DocumentItem?
    @State private var folders: [DocumentItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.s("documents.moveSelected.title"))
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                Button {
                    currentFolderID = nil
                    Task {
                        await loadFolders(currentID: nil)
                    }
                } label: {
                    Image(systemName: "house")
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await loadFolders(currentID: currentFolder?.parentID)
                    }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(currentFolder?.parentID == nil)

                Text(currentFolder?.name ?? L10n.s("documents.moveSelected.root"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            List(folders) { folder in
                Button {
                    Task {
                        await loadFolders(currentID: folder.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.yellow)
                        Text(folder.name)
                        Spacer(minLength: 0)
                        Text("\(folder.children)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            HStack {
                Spacer()
                Button(L10n.s("common.cancel")) {
                    dismiss()
                }
                Button(L10n.s("documents.moveSelected.action")) {
                    if let destinationID = currentFolder?.id {
                        onMove(destinationID)
                    }
                }
                .disabled(isLoading || currentFolder == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
        .task {
            currentFolderID = initialFolderID
            await loadFolders(currentID: initialFolderID)
        }
    }

    @MainActor
    private func loadFolders(currentID: Int64?) async {
        guard let token,
            !token.isEmpty
        else {
            errorMessage = L10n.s("documents.error.loginRequired")
            return
        }
        if isLoading {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            let items = try await service.getDocumentItems(token: token, currentID: currentID)
            guard let volume = items.first(where: { $0.type == DocumentType.volume.rawValue }) else {
                folders = []
                currentFolder = nil
                errorMessage = L10n.s("documents.error.load")
                return
            }
            let resolved: DocumentItem
            if let currentID,
                let current = items.first(where: { $0.id == currentID })
            {
                resolved = current
            } else {
                resolved = volume
            }
            currentFolderID = resolved.id
            currentFolder = resolved
            folders = items
                .filter {
                    $0.type == DocumentType.folder.rawValue && $0.parentID == resolved.id
                        && $0.accessRole == nil
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            folders = []
            currentFolder = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.s("documents.error.load")
        }
    }
}

private struct DocumentNameSheet: View {
    let title: String
    let fieldLabel: String
    let actionTitle: String
    @Binding var name: String
    @Binding var isPresented: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(fieldLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(fieldLabel, text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(L10n.s("common.cancel")) {
                    isPresented = false
                }
                Button(actionTitle) {
                    onSubmit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
