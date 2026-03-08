import AppKit
import Foundation

@MainActor
final class DownloadDirectoryAccessManager {
    static let shared = DownloadDirectoryAccessManager()

    private let bookmarkDefaultsKey = "downloads.securityScopedBookmark"
    private var activeScopedURL: URL?

    private init() {}

    func ensureAccessForDocumentsTab() {
        _ = accessibleDownloadsDirectoryURL(promptIfNeeded: true)
    }

    func accessibleDownloadsDirectoryURL(promptIfNeeded: Bool) -> URL? {
        if let resolved = resolveWithoutPrompt() {
            return resolved
        }
        guard promptIfNeeded else {
            return nil
        }
        return promptForDownloadsDirectoryAccess()
    }

    private func resolveWithoutPrompt() -> URL? {
        if let activeScopedURL,
            canAccessDirectory(activeScopedURL)
        {
            return activeScopedURL
        }

        let defaultDownloadsURL = systemDownloadsDirectoryURL()
        if canAccessDirectory(defaultDownloadsURL) {
            return defaultDownloadsURL
        }

        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else {
            return nil
        }

        var isStale = false
        guard
            let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        else {
            UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
            return nil
        }

        let didStartAccess = bookmarkedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
            return nil
        }

        guard canAccessDirectory(bookmarkedURL) else {
            bookmarkedURL.stopAccessingSecurityScopedResource()
            UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
            return nil
        }

        activeScopedURL = bookmarkedURL
        if isStale,
            let refreshedBookmark = try? bookmarkedURL.bookmarkData(options: .withSecurityScope)
        {
            UserDefaults.standard.set(refreshedBookmark, forKey: bookmarkDefaultsKey)
        }

        return bookmarkedURL
    }

    private func promptForDownloadsDirectoryAccess() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.directoryURL = systemDownloadsDirectoryURL()
        panel.title = L10n.s("downloadsPermission.title")
        panel.message = L10n.s("downloadsPermission.message")
        panel.prompt = L10n.s("downloadsPermission.prompt")

        guard panel.runModal() == .OK,
            let selectedURL = panel.url
        else {
            return nil
        }

        let didStartAccess = selectedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            return nil
        }

        guard canAccessDirectory(selectedURL) else {
            selectedURL.stopAccessingSecurityScopedResource()
            return nil
        }

        guard let bookmarkData = try? selectedURL.bookmarkData(options: .withSecurityScope) else {
            selectedURL.stopAccessingSecurityScopedResource()
            return nil
        }

        activeScopedURL = selectedURL
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkDefaultsKey)
        return selectedURL
    }

    private func canAccessDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
            return true
        } catch {
            return false
        }
    }

    private func systemDownloadsDirectoryURL() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
    }
}