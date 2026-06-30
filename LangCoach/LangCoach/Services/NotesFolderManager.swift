import Foundation
import Observation
import SwiftData

/// Manages a single "mounted" notes folder: the user picks a folder once, and its
/// supported files are imported as `StudyDocument`s and kept in sync — both on
/// launch and live while the app is open (via `FolderWatcher`).
///
/// Access to the folder persists across launches through a security-scoped
/// bookmark (stored in UserDefaults; not secret). The app is sandboxed, so the
/// resolved URL's security scope is started once and held for the app's lifetime;
/// child files inherit that access.
@MainActor
@Observable
final class NotesFolderManager {
    nonisolated private let container: ModelContainer
    nonisolated private let coach: Coach
    nonisolated private let googleAuth: GoogleAuth

    /// The currently linked folder, if any.
    private(set) var folderURL: URL? = nil
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date? = nil

    /// Display name of the linked folder (last path component).
    var folderName: String? { folderURL?.lastPathComponent }
    var isLinked: Bool { folderURL != nil }

    private var watcher: FolderWatcher? = nil
    /// URL whose security scope is currently held open, so we can release it.
    private var accessedURL: URL? = nil
    private var didStart = false

    private static let bookmarkKey = "notesFolderBookmark"

    nonisolated init(container: ModelContainer, coach: Coach, googleAuth: GoogleAuth) {
        self.container = container
        self.coach = coach
        self.googleAuth = googleAuth
    }

    /// Restores any previously linked folder and begins watching. Call once after
    /// launch (from the main actor).
    func start() {
        guard !didStart else { return }
        didStart = true
        restoreFromBookmark()
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Linking

    /// Link `url` as the notes folder: persist a bookmark, begin watching, sync.
    func chooseFolder(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        activate(url)
    }

    /// Stop watching and forget the folder. Already-imported notes are kept.
    func unlink() {
        watcher?.stop()
        watcher = nil
        releaseAccess()
        folderURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    private func restoreFromBookmark() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }
        // Re-save a refreshed bookmark if the old one went stale.
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        activate(url)
    }

    /// Begin security-scoped access, start watching, and run an initial sync.
    private func activate(_ url: URL) {
        releaseAccess()
        guard url.startAccessingSecurityScopedResource() else { return }
        accessedURL = url
        folderURL = url

        watcher?.stop()
        let watcher = FolderWatcher(url: url) { [weak self] in
            Task { @MainActor in await self?.sync() }
        }
        watcher.start()
        self.watcher = watcher

        Task { await sync() }
    }

    private func releaseAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    // MARK: - Sync

    /// Scan the folder and reconcile it against stored documents: import new
    /// files, re-import changed ones. Deleted files are intentionally left in
    /// place to avoid data loss.
    func sync() async {
        guard let folderURL, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false; lastSyncDate = .now }

        let files = scanFiles(in: folderURL)

        // Resolve a Google token once (if signed in) so private .gdoc shortcuts in
        // the folder can be fetched via the Drive API.
        let googleToken = await googleAuth.validAccessToken()

        // Map existing folder-sourced docs by their source path.
        let descriptor = FetchDescriptor<StudyDocument>(
            predicate: #Predicate { $0.sourcePath != "" }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        var byPath: [String: StudyDocument] = [:]
        for doc in existing { byPath[doc.sourcePath] = doc }

        // Cache of mirrored folders by their source directory path, so repeated
        // files in the same subdirectory reuse one NoteFolder.
        let folderDescriptor = FetchDescriptor<NoteFolder>(
            predicate: #Predicate { $0.sourcePath != "" }
        )
        var folderByPath: [String: NoteFolder] = [:]
        for f in (try? context.fetch(folderDescriptor)) ?? [] { folderByPath[f.sourcePath] = f }

        var touched: [StudyDocument] = []
        for (url, modified) in files {
            let path = url.path
            if let doc = byPath[path] {
                // Re-import only if the file changed since we last read it.
                guard let modified, let stored = doc.sourceModified, modified > stored else { continue }
                if let extracted = await extract(url, token: googleToken) {
                    doc.title = extracted.title
                    doc.text = extracted.text
                    doc.formattedData = extracted.formatted
                    doc.sourceModified = modified
                    touched.append(doc)
                }
            } else if let extracted = await extract(url, token: googleToken) {
                let doc = StudyDocument(
                    title: extracted.title,
                    sourceFilename: url.lastPathComponent,
                    text: extracted.text,
                    formattedData: extracted.formatted,
                    sourcePath: path,
                    sourceModified: modified,
                    // Mirror the on-disk subdirectory structure into NoteFolders.
                    folder: folder(for: url, root: folderURL, cache: &folderByPath)
                )
                context.insert(doc)
                touched.append(doc)
            }
        }

        guard !touched.isEmpty else { return }
        try? context.save()
        distill(touched)
    }

    /// Find-or-create the chain of `NoteFolder`s mirroring `fileURL`'s parent
    /// directories, relative to the mounted `root`, and return the deepest one
    /// (nil when the file sits directly in the root). Folders are keyed by their
    /// absolute source path so re-syncs reuse them instead of duplicating.
    private func folder(for fileURL: URL, root: URL, cache: inout [String: NoteFolder]) -> NoteFolder? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let dirComponents = fileURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        // The subdirectory components below the mounted root.
        guard dirComponents.count > rootComponents.count else { return nil }
        let relative = Array(dirComponents[rootComponents.count...])

        var parent: NoteFolder? = nil
        var path = root.standardizedFileURL.path
        for name in relative {
            path += "/" + name
            if let existing = cache[path] {
                parent = existing
                continue
            }
            let created = NoteFolder(name: name, sourcePath: path, parent: parent)
            context.insert(created)
            cache[path] = created
            parent = created
        }
        return parent
    }

    /// Enumerate supported files in the folder tree with their modification dates.
    private func scanFiles(in folderURL: URL) -> [(URL, Date?)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [(URL, Date?)] = []
        for case let url as URL in enumerator {
            guard DocumentImporter.allowedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == false { continue }
            result.append((url, values?.contentModificationDate))
        }
        return result
    }

    private func extract(_ url: URL, token: String?) async -> (title: String, text: String, formatted: Data?)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? await DocumentImporter.load(from: url, googleToken: token)
    }

    /// Distill newly imported / changed notes into study memory, mirroring the
    /// behavior of a manual import.
    private func distill(_ docs: [StudyDocument]) {
        guard coach.hasKey else { return }
        for doc in docs {
            let text = doc.text
            Task { [weak self] in
                guard let self else { return }
                let memory = try? await self.coach.distillNotes(text)
                if let memory, !memory.isEmpty {
                    doc.studyMemory = memory
                    try? self.context.save()
                }
            }
        }
    }
}
