import AppKit
import AuditorModels
import AuditorStore
import Foundation
import Observation

/// Brokers user folder grants: `NSOpenPanel` → security-scoped bookmark → GRDB.
/// Every engine read of a watched folder must go through `AccessToken`.
@Observable
@MainActor
final class FolderAccessManager {
    struct AccessToken: Sendable {
        let url: URL
        private let stop: @Sendable () -> Void

        init(url: URL, stop: @escaping @Sendable () -> Void) {
            self.url = url
            self.stop = stop
        }

        func end() { stop() }
    }

    struct WatchedFolder: Identifiable, Equatable, Sendable {
        var id: String { path }
        let path: String
        let displayName: String
        let cloudMode: CloudScanMode
        let isStale: Bool
        let addedAt: Date
    }

    private(set) var folders: [WatchedFolder] = []
    private(set) var lastError: String?

    private let database: AuditorDatabase
    private var bookmarkByPath: [String: Data] = [:]

    init(database: AuditorDatabase) {
        self.database = database
        reloadFromStore()
    }

    func reloadFromStore() {
        do {
            let stored = try database.loadWatchedFolders()
            var resolved: [WatchedFolder] = []
            var bookmarks: [String: Data] = [:]
            for item in stored {
                bookmarks[item.path] = item.bookmark
                var isStale = item.bookmark == nil
                if let data = item.bookmark {
                    do {
                        let resolution = try SecurityScopedBookmark.resolve(data)
                        isStale = resolution.isStale
                    } catch {
                        isStale = true
                    }
                }
                resolved.append(WatchedFolder(
                    path: item.path,
                    displayName: (item.path as NSString).lastPathComponent,
                    cloudMode: item.cloudMode,
                    isStale: isStale,
                    addedAt: item.addedAt
                ))
            }
            folders = resolved
            bookmarkByPath = bookmarks
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Presents an open panel and persists a security-scoped bookmark on success.
    @discardableResult
    func presentFolderPicker(cloudMode: CloudScanMode = .metadataOnly) -> WatchedFolder? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Grant Access"
        panel.message = "FolderLint can only audit folders you explicitly select."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return addFolder(url: url, cloudMode: cloudMode)
    }

    @discardableResult
    func addFolder(url: URL, cloudMode: CloudScanMode = .metadataOnly) -> WatchedFolder? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let bookmark = try SecurityScopedBookmark.create(from: url)
            let path = url.standardizedFileURL.path
            let stored = StoredWatchedFolder(
                path: path,
                bookmark: bookmark,
                cloudMode: cloudMode,
                addedAt: Date()
            )
            try database.saveWatchedFolder(stored)
            bookmarkByPath[path] = bookmark
            let folder = WatchedFolder(
                path: path,
                displayName: url.lastPathComponent,
                cloudMode: cloudMode,
                isStale: false,
                addedAt: stored.addedAt
            )
            folders.removeAll { $0.path == path }
            folders.append(folder)
            folders.sort { $0.addedAt < $1.addedAt }
            lastError = nil
            return folder
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func removeFolder(_ folder: WatchedFolder) {
        do {
            try database.removeWatchedFolder(path: folder.path)
            bookmarkByPath.removeValue(forKey: folder.path)
            folders.removeAll { $0.path == folder.path }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-grants a stale bookmark by asking the user to reselect the folder.
    @discardableResult
    func regrant(_ folder: WatchedFolder) -> WatchedFolder? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Restore Access"
        panel.message = "“\(folder.displayName)” moved or was renamed. Select it again to restore access."
        panel.directoryURL = URL(fileURLWithPath: folder.path).deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        removeFolder(folder)
        return addFolder(url: url, cloudMode: folder.cloudMode)
    }

    /// Starts security-scoped access for a watched folder. Caller must `end()` the token.
    func beginAccess(to folder: WatchedFolder) throws -> AccessToken {
        guard let data = bookmarkByPath[folder.path] else {
            throw SecurityScopedBookmark.BookmarkError.resolutionFailed
        }
        let resolution = try SecurityScopedBookmark.resolve(data)
        if resolution.isStale {
            throw SecurityScopedBookmark.BookmarkError.staleNeedsRegrant
        }
        let url = resolution.url
        guard url.startAccessingSecurityScopedResource() else {
            throw SecurityScopedBookmark.BookmarkError.resolutionFailed
        }
        return AccessToken(url: url) {
            url.stopAccessingSecurityScopedResource()
        }
    }

    var hasUsableFolder: Bool {
        folders.contains { !$0.isStale }
    }
}
