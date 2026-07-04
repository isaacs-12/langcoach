import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Something being dragged in the Library sidebar — either a note or a folder.
enum DragItem {
    case document(StudyDocument)
    case folder(NoteFolder)
}

/// Holds the in-flight drag across rows. The dragged values are stashed here on
/// `.onDrag` and read back on `.onDrop`, so the dropped provider payload is
/// irrelevant (the drag never leaves the app). Dragging a note that's part of a
/// multi-selection carries every selected note at once.
@Observable
final class DragContext {
    var items: [DragItem] = []
}

/// Reparent a single note or folder under `target` (nil = top level), without
/// saving. Returns whether the move was applied — folder moves that would create
/// a cycle (into itself or a descendant) are rejected.
@MainActor
private func reparent(_ item: DragItem, to target: NoteFolder?) -> Bool {
    switch item {
    case .document(let doc):
        doc.folder = target
        return true
    case .folder(let folder):
        if let target {
            guard folder !== target, !folder.contains(target) else { return false }
        }
        folder.parent = target
        return true
    }
}

/// Reparent one or more notes/folders under `target` (nil = top level), saving
/// once if anything changed.
@MainActor
func moveItems(_ items: [DragItem], to target: NoteFolder?, context: ModelContext) {
    var changed = false
    for item in items where reparent(item, to: target) { changed = true }
    if changed { try? context.save() }
}

// MARK: - Sorting helpers

/// How the note lists are ordered. Applies uniformly to the top-level notes and
/// the notes inside every folder. Persisted via `@AppStorage`, so it's stored by
/// raw value.
enum NoteSortOrder: String, CaseIterable, Identifiable {
    case dateDesc, dateAsc, titleAsc, titleDesc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateDesc: return "Newest first"
        case .dateAsc:  return "Oldest first"
        case .titleAsc: return "Title (A–Z)"
        case .titleDesc: return "Title (Z–A)"
        }
    }

    func sorted(_ docs: [StudyDocument]) -> [StudyDocument] {
        switch self {
        case .dateDesc: return docs.sorted { $0.importedAt > $1.importedAt }
        case .dateAsc:  return docs.sorted { $0.importedAt < $1.importedAt }
        case .titleAsc:
            return docs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .titleDesc:
            return docs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedDescending }
        }
    }
}

extension NoteFolder {
    /// Subfolders sorted by name for stable display.
    var sortedChildren: [NoteFolder] {
        children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Move-to submenu

/// A "Move to ▸" submenu listing every folder (indented by depth) plus a
/// top-level option. Invalid destinations are disabled.
struct MoveToMenu: View {
    let items: [DragItem]
    let roots: [NoteFolder]
    @Environment(\.modelContext) private var context

    var body: some View {
        Menu {
            Button("Top level") { moveItems(items, to: nil, context: context) }
                .disabled(allAlreadyIn(nil))
            Divider()
            ForEach(roots) { root in
                rows(for: root, depth: 0)
            }
        } label: {
            Label(items.count > 1 ? "Move \(items.count) items to" : "Move to",
                  systemImage: "folder")
        }
    }

    // Returns `AnyView` rather than `some View`: the function recurses on
    // subfolders, and a recursive `@ViewBuilder` returning an opaque type would
    // define that type in terms of itself (a compiler error). Type-erasing breaks
    // the cycle.
    private func rows(for folder: NoteFolder, depth: Int) -> AnyView {
        AnyView(
            Group {
                Button {
                    moveItems(items, to: folder, context: context)
                } label: {
                    Text(String(repeating: "    ", count: depth) + folder.name)
                }
                .disabled(isInvalid(folder))
                ForEach(folder.sortedChildren) { child in
                    rows(for: child, depth: depth + 1)
                }
            }
        )
    }

    private func isCurrentParent(_ item: DragItem, _ target: NoteFolder?) -> Bool {
        switch item {
        case .document(let doc): return doc.folder === target
        case .folder(let f): return f.parent === target
        }
    }

    /// A destination is only redundant when *every* item already lives there.
    private func allAlreadyIn(_ target: NoteFolder?) -> Bool {
        !items.isEmpty && items.allSatisfy { isCurrentParent($0, target) }
    }

    /// Disabled when the move is a no-op for all items, or would place any
    /// dragged folder inside itself or one of its own descendants.
    private func isInvalid(_ target: NoteFolder) -> Bool {
        if allAlreadyIn(target) { return true }
        return items.contains { item in
            if case .folder(let f) = item { return f === target || f.contains(target) }
            return false
        }
    }
}

// MARK: - Document row

struct DocumentRow: View {
    let doc: StudyDocument
    let roots: [NoteFolder]
    @Binding var selection: Set<StudyDocument>
    @Bindable var drag: DragContext
    /// Create a new folder containing the given notes (and rename it inline).
    let onNewFolder: ([StudyDocument]) -> Void
    /// Open a note in its own reader window (double-click or context menu).
    let onOpen: (StudyDocument) -> Void
    @Environment(\.modelContext) private var context

    /// The notes this row's actions apply to: the whole selection when this row
    /// is part of a multi-selection, otherwise just this note.
    private var affectedDocs: [StudyDocument] {
        selection.contains(doc) && selection.count > 1 ? Array(selection) : [doc]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(doc.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text(doc.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("\(doc.wordCount) words · \(doc.importedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .tag(doc)
        .contentShape(Rectangle())
        // Double-click opens the note in its own reader window; single clicks
        // still fall through to the List for selection.
        .onTapGesture(count: 2) { onOpen(doc) }
        .onDrag {
            let docs = affectedDocs
            drag.items = docs.map { .document($0) }
            let label = docs.count > 1 ? "\(docs.count) notes" : doc.title
            return NSItemProvider(object: label as NSString)
        }
        .contextMenu {
            let docs = affectedDocs
            Button {
                onOpen(doc)
            } label: {
                Label("Open in New Window", systemImage: "arrow.up.forward.square")
            }
            Divider()
            Button {
                onNewFolder(docs)
            } label: {
                Label(docs.count > 1 ? "New Folder with \(docs.count) Notes" : "New Folder with Note",
                      systemImage: "folder.badge.plus")
            }
            MoveToMenu(items: docs.map { .document($0) }, roots: roots)
            Divider()
            Button(role: .destructive) {
                for d in docs {
                    selection.remove(d)
                    context.delete(d)
                }
                try? context.save()
            } label: {
                Label(docs.count > 1 ? "Delete \(docs.count) Notes" : "Delete",
                      systemImage: "trash")
            }
        }
    }
}

// MARK: - Folder row (recursive)

struct FolderRow: View {
    let folder: NoteFolder
    let roots: [NoteFolder]
    @Binding var selection: Set<StudyDocument>
    @Binding var expanded: Set<PersistentIdentifier>
    @Bindable var drag: DragContext
    let sort: NoteSortOrder
    let onRename: (NoteFolder) -> Void
    let onNewSubfolder: (NoteFolder) -> Void
    let onNewFolder: ([StudyDocument]) -> Void
    let onDelete: (NoteFolder) -> Void
    let onOpen: (StudyDocument) -> Void
    @Environment(\.modelContext) private var context
    @State private var targeted = false

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expanded.contains(folder.persistentModelID) },
            set: { newValue in
                if newValue { expanded.insert(folder.persistentModelID) }
                else { expanded.remove(folder.persistentModelID) }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(folder.sortedChildren) { child in
                FolderRow(
                    folder: child, roots: roots, selection: $selection,
                    expanded: $expanded, drag: drag, sort: sort,
                    onRename: onRename, onNewSubfolder: onNewSubfolder,
                    onNewFolder: onNewFolder, onDelete: onDelete, onOpen: onOpen
                )
            }
            ForEach(sort.sorted(folder.documents)) { doc in
                DocumentRow(doc: doc, roots: roots, selection: $selection,
                            drag: drag, onNewFolder: onNewFolder, onOpen: onOpen)
            }
        } label: {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Theme.accent)
            Text(folder.name).font(.body.weight(.medium)).lineLimit(1)
            Spacer()
            let count = folder.documents.count
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(targeted ? Theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onDrag {
            drag.items = [.folder(folder)]
            return NSItemProvider(object: folder.name as NSString)
        }
        .onDrop(of: [.text], isTargeted: $targeted) { _ in
            guard !drag.items.isEmpty else { return false }
            moveItems(drag.items, to: folder, context: context)
            expanded.insert(folder.persistentModelID)
            drag.items = []
            return true
        }
        .contextMenu {
            Button { onNewSubfolder(folder) } label: {
                Label("New Subfolder", systemImage: "folder.badge.plus")
            }
            Button { onRename(folder) } label: {
                Label("Rename…", systemImage: "pencil")
            }
            MoveToMenu(items: [.folder(folder)], roots: roots)
            Divider()
            Button(role: .destructive) { onDelete(folder) } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
}
