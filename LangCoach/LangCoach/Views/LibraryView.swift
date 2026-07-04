import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(Coach.self) private var coach
    @Environment(GoogleAuth.self) private var googleAuth
    @Environment(NotesFolderManager.self) private var folderManager
    @Query(sort: \StudyDocument.importedAt, order: .reverse) private var documents: [StudyDocument]
    @Query private var folders: [NoteFolder]

    /// What the (single) file picker is currently choosing. SwiftUI only honors
    /// one `.fileImporter` per view, so files and folders share one importer whose
    /// content types and result handling switch on this.
    private enum PickTarget { case files, folder }

    @State private var selection: Set<StudyDocument> = []
    /// How notes are ordered in every list (top level and inside folders).
    @AppStorage("libraryNoteSort") private var noteSort: NoteSortOrder = .dateDesc
    @State private var pickTarget: PickTarget = .files
    @State private var picking = false
    @State private var importError: String?
    @State private var extracting: StudyDocument?
    /// IDs of documents currently having their study memory distilled.
    @State private var distilling: Set<PersistentIdentifier> = []
    /// Expanded folder IDs (session-only disclosure state).
    @State private var expandedFolders: Set<PersistentIdentifier> = []
    @State private var drag = DragContext()
    @State private var renamingFolder: NoteFolder?
    @State private var renameText = ""
    @State private var pendingDeleteFolder: NoteFolder?
    @State private var rootDropTargeted = false

    /// Top-level folders, sorted by name.
    private var rootFolders: [NoteFolder] {
        folders
            .filter { $0.parent == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Notes not filed under any folder, ordered by the chosen sort.
    private var rootDocuments: [StudyDocument] {
        noteSort.sorted(documents.filter { $0.folder == nil })
    }

    var body: some View {
        Group {
            if documents.isEmpty && folders.isEmpty {
                CalloutView(
                    systemImage: "tray.and.arrow.down.fill",
                    title: "Import your class notes",
                    message: "Export your Korean lessons from Google Docs (File ▸ Download ▸ .docx, PDF, or plain text) and import them here. The text is stored locally so you can study offline.",
                    actionTitle: "Import notes…",
                    action: { pick(.files) },
                    secondaryActionTitle: "Or link a notes folder…",
                    secondaryAction: { pick(.folder) }
                )
            } else {
                HSplitView {
                    docList
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    docDetail
                        .frame(minWidth: 360, maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            if !documents.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
            ToolbarItem(placement: .primaryAction) {
                folderMenu
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createFolder(parent: nil)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("Create a new folder to organize your notes")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    pick(.files)
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .help("Import notes from your file system")
            }
        }
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: pickTarget == .folder ? [.folder] : DocumentImporter.allowedContentTypes,
            allowsMultipleSelection: pickTarget == .files
        ) { result in
            switch pickTarget {
            case .files: handleImport(result)
            case .folder: handleFolderLink(result)
            }
        }
        .alert("Import problem", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $extracting) { doc in
            VocabExtractionSheet(document: doc)
        }
        .alert("Rename folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder name", text: $renameText)
            Button("Rename") {
                if let folder = renamingFolder {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        folder.name = trimmed
                        try? context.save()
                    }
                }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { pendingDeleteFolder != nil },
                set: { if !$0 { pendingDeleteFolder = nil } }
            ),
            presenting: pendingDeleteFolder
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                context.delete(folder)
                try? context.save()
                pendingDeleteFolder = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteFolder = nil }
        } message: { _ in
            Text("Subfolders are removed too. The notes inside are kept and moved to the top level.")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort notes by", selection: $noteSort) {
                ForEach(NoteSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort notes", systemImage: "arrow.up.arrow.down")
        }
        .help("Change how notes are ordered")
    }

    @ViewBuilder
    private var folderMenu: some View {
        Menu {
            if folderManager.isLinked {
                Section(folderManager.folderName ?? "Linked folder") {
                    Button {
                        Task { await folderManager.sync() }
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(folderManager.isSyncing)
                    Button(role: .destructive) {
                        folderManager.unlink()
                    } label: {
                        Label("Unlink folder", systemImage: "xmark.circle")
                    }
                }
            } else {
                Button {
                    pick(.folder)
                } label: {
                    Label("Link notes folder…", systemImage: "folder.badge.plus")
                }
            }

            if googleAuth.isConfigured {
                Divider()
                googleAccountSection
            }
        } label: {
            Label("Notes folder", systemImage: folderManager.isLinked ? "folder.fill" : "folder.badge.gearshape")
        }
        .help(folderManager.isLinked
              ? "Linked to \(folderManager.folderName ?? "a folder") — notes sync automatically"
              : "Link a folder to import and auto-sync its notes")
    }

    /// Google sign-in controls — only shown when an OAuth client ID is configured.
    /// Signing in lets the app read *private* Google Docs (.gdoc shortcuts) from a
    /// linked Drive folder.
    @ViewBuilder
    private var googleAccountSection: some View {
        Section("Google Drive") {
            if googleAuth.isSignedIn {
                if let email = googleAuth.email {
                    Text(email).foregroundStyle(.secondary)
                }
                Button {
                    Task { await folderManager.sync() }
                } label: {
                    Label("Import private Google Docs", systemImage: "lock.open")
                }
                .disabled(!folderManager.isLinked || folderManager.isSyncing)
                Button(role: .destructive) {
                    googleAuth.signOut()
                } label: {
                    Label("Sign out of Google", systemImage: "person.crop.circle.badge.xmark")
                }
            } else {
                Button {
                    signInToGoogle()
                } label: {
                    Label("Sign in to Google…", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
    }

    private func signInToGoogle() {
        Task {
            do {
                try await googleAuth.signIn()
                // Pull private docs from the linked folder now that we can.
                if folderManager.isLinked { await folderManager.sync() }
            } catch GoogleAuthError.cancelled {
                // user dismissed — no-op
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private var docList: some View {
        List(selection: $selection) {
            // Top-level drop zone: drag a note or folder here to move it out of
            // any folder. Doubles as a header anchoring the tree.
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .foregroundStyle(.secondary)
                Text("All Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(rootDropTargeted ? Theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onDrop(of: [.text], isTargeted: $rootDropTargeted) { _ in
                guard !drag.items.isEmpty else { return false }
                moveItems(drag.items, to: nil, context: context)
                drag.items = []
                return true
            }

            ForEach(rootFolders) { folder in
                FolderRow(
                    folder: folder, roots: rootFolders, selection: $selection,
                    expanded: $expandedFolders, drag: drag, sort: noteSort,
                    onRename: beginRename, onNewSubfolder: { createFolder(parent: $0) },
                    onNewFolder: { createFolder(withSelection: $0) },
                    onDelete: { pendingDeleteFolder = $0 }
                )
            }

            ForEach(rootDocuments) { doc in
                DocumentRow(doc: doc, roots: rootFolders, selection: $selection,
                            drag: drag, onNewFolder: { createFolder(withSelection: $0) })
            }
        }
    }

    /// The note shown in the detail pane: the single selected note, or the
    /// newest note when nothing is selected. Nil while several notes are selected.
    private var detailDoc: StudyDocument? {
        if selection.count == 1 { return selection.first }
        if selection.isEmpty { return documents.first }
        return nil
    }

    @ViewBuilder
    private var docDetail: some View {
        if selection.count > 1 {
            CalloutView(
                systemImage: "checklist",
                title: "\(selection.count) notes selected",
                message: "Drag them into a folder, or right-click to move or delete them together."
            )
        } else if let doc = detailDoc {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title).font(.title2.bold())
                        Text(doc.sourceFilename).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        extracting = doc
                    } label: {
                        Label("Extract vocab", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                Divider()
                if let data = doc.formattedData {
                    // Give the memory a bounded, scrollable box so a long vocab list
                    // neither clips nor collapses against the rich-text view below.
                    memorySection(for: doc, capHeight: 300)
                    RichTextView(data: data)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            memorySection(for: doc)
                            Text(doc.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
            }
        } else {
            CalloutView(
                systemImage: "doc.text",
                title: "No document selected",
                message: "Select a note from the list to read it and pull out vocabulary."
            )
        }
    }

    // MARK: - Study memory

    /// `capHeight` bounds the study-memory text to a scrollable box (used where the
    /// section shares space with the rich-text view, so a long list can't clip).
    @ViewBuilder
    private func memorySection(for doc: StudyDocument, capHeight: CGFloat? = nil) -> some View {
        let isDistilling = distilling.contains(doc.persistentModelID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Theme.accent)
                Text("Study memory")
                    .font(.headline)
                Spacer()
                if isDistilling {
                    ProgressView().controlSize(.small)
                } else {
                    Button(doc.hasMemory ? "Regenerate" : "Generate") {
                        distill(doc)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!coach.hasKey)
                }
            }
            if doc.hasMemory {
                let memoryText = Text(doc.studyMemory)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let capHeight {
                    // minHeight floor keeps the box from collapsing to nothing next
                    // to the greedy rich-text view; it scrolls when vocab is long.
                    ScrollView { memoryText.padding(.trailing, 4) }
                        .frame(minHeight: 160, maxHeight: capHeight)
                } else {
                    memoryText
                }
                if !doc.themes.isEmpty {
                    Divider()
                    Text("Conversation themes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(doc.themes, id: \.self) { theme in
                            Text(theme)
                                .font(.caption.weight(.medium))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                                .background(Theme.accent.opacity(0.14), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(coach.hasKey
                     ? "A compact summary used for translation and conversation practice. Generated automatically on import."
                     : "Set up an API key to distill this note into practice context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top])
    }

    private func distill(_ doc: StudyDocument) {
        let id = doc.persistentModelID
        guard coach.hasKey, !distilling.contains(id) else { return }
        distilling.insert(id)
        // Prefer bold-annotated text so the distiller can prioritize what the
        // student emphasized; fall back to plain text when there's no formatting.
        let text = doc.formattedData.flatMap { DocumentImporter.boldAnnotatedText(fromRTF: $0) } ?? doc.text
        Task {
            do {
                let memory = try await coach.distillNotes(text)
                await MainActor.run {
                    if !memory.isEmpty {
                        doc.studyMemory = memory
                        try? context.save()
                    }
                    distilling.remove(id)
                }
            } catch {
                // Surface the failure instead of silently leaving an empty memory
                // (which reads as "no vocab"). Retries already happened in Coach.
                await MainActor.run {
                    distilling.remove(id)
                    importError = "Couldn't generate study memory for “\(doc.title)”: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Actions

    /// Set what we're choosing, then present the shared file importer. Order
    /// matters: `pickTarget` must be set before `picking` so the importer reads
    /// the right content types when it presents.
    private func pick(_ target: PickTarget) {
        pickTarget = target
        picking = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            // `.gdoc` shortcuts require a network fetch, so importing is async.
            Task { await importURLs(urls) }
        }
    }

    @MainActor
    private func importURLs(_ urls: [URL]) async {
        var failures: [String] = []
        var imported: [StudyDocument] = []
        // Resolve a Google token once so private .gdoc shortcuts can be fetched.
        let googleToken = await googleAuth.validAccessToken()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let (title, text, formatted) = try await DocumentImporter.load(from: url, googleToken: googleToken)
                let doc = StudyDocument(title: title, sourceFilename: url.lastPathComponent, text: text, formattedData: formatted)
                context.insert(doc)
                selection = [doc]
                imported.append(doc)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        try? context.save()
        // Distill each new note into a compact study memory in the background.
        if coach.hasKey {
            for doc in imported { distill(doc) }
        }
        if !failures.isEmpty {
            importError = failures.joined(separator: "\n")
        }
    }

    private func handleFolderLink(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            folderManager.chooseFolder(url)
        }
    }

    // MARK: - Folders

    /// Create a folder under `parent` (nil = top level), reveal it, and open the
    /// rename prompt so the user can name it immediately.
    private func createFolder(parent: NoteFolder?) {
        let folder = NoteFolder(name: "New Folder", parent: parent)
        context.insert(folder)
        try? context.save()
        if let parent { expandedFolders.insert(parent.persistentModelID) }
        beginRename(folder)
    }

    /// Create a folder containing `docs`, then open the rename prompt. The folder
    /// is placed alongside the notes: under their shared parent when they all live
    /// in the same folder, otherwise at the top level.
    private func createFolder(withSelection docs: [StudyDocument]) {
        guard !docs.isEmpty else { return }
        let parents = Set(docs.map { $0.folder?.persistentModelID })
        let parent = parents.count == 1 ? docs.first?.folder : nil
        let folder = NoteFolder(name: "New Folder", parent: parent)
        context.insert(folder)
        for doc in docs { doc.folder = folder }
        try? context.save()
        if let parent { expandedFolders.insert(parent.persistentModelID) }
        expandedFolders.insert(folder.persistentModelID)
        beginRename(folder)
    }

    private func beginRename(_ folder: NoteFolder) {
        renameText = folder.name
        renamingFolder = folder
    }
}
