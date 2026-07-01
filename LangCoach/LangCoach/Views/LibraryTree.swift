import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Something being dragged in the Library sidebar — either a note or a folder.
enum DragItem {
    case document(StudyDocument)
    case folder(NoteFolder)
}

/// Holds the in-flight drag across rows. The dragged value is stashed here on
/// `.onDrag` and read back on `.onDrop`, so the dropped provider payload is
/// irrelevant (the drag never leaves the app).
@Observable
final class DragContext {
    var item: DragItem? = nil
}

/// Reparent a note or folder under `target` (nil = top level). Folder moves that
/// would create a cycle (into itself or a descendant) are rejected.
@MainActor
func moveItem(_ item: DragItem, to target: NoteFolder?, context: ModelContext) {
    switch item {
    case .document(let doc):
        doc.folder = target
    case .folder(let folder):
        if let target {
            guard folder !== target, !folder.contains(target) else { return }
        }
        folder.parent = target
    }
    try? context.save()
}

// MARK: - Sorting helpers

extension NoteFolder {
    /// Subfolders sorted by name for stable display.
    var sortedChildren: [NoteFolder] {
        children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// Notes filed directly here, newest first (matching the flat list's order).
    var sortedDocuments: [StudyDocument] {
        documents.sorted { $0.importedAt > $1.importedAt }
    }
}

// MARK: - Move-to submenu

/// A "Move to ▸" submenu listing every folder (indented by depth) plus a
/// top-level option. Invalid destinations are disabled.
struct MoveToMenu: View {
    let item: DragItem
    let roots: [NoteFolder]
    @Environment(\.modelContext) private var context

    var body: some View {
        Menu {
            Button("Top level") { moveItem(item, to: nil, context: context) }
                .disabled(isCurrentParent(nil))
            Divider()
            ForEach(roots) { root in
                rows(for: root, depth: 0)
            }
        } label: {
            Label("Move to", systemImage: "folder")
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
                    moveItem(item, to: folder, context: context)
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

    private func isCurrentParent(_ target: NoteFolder?) -> Bool {
        switch item {
        case .document(let doc): return doc.folder === target
        case .folder(let f): return f.parent === target
        }
    }

    private func isInvalid(_ target: NoteFolder) -> Bool {
        if isCurrentParent(target) { return true }
        if case .folder(let f) = item { return f.contains(target) }
        return false
    }
}

// MARK: - Document row

struct DocumentRow: View {
    let doc: StudyDocument
    let roots: [NoteFolder]
    @Binding var selection: StudyDocument?
    @Bindable var drag: DragContext
    @Environment(\.modelContext) private var context

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
        .onDrag {
            drag.item = .document(doc)
            return NSItemProvider(object: doc.title as NSString)
        }
        .contextMenu {
            MoveToMenu(item: .document(doc), roots: roots)
            Divider()
            Button(role: .destructive) {
                if selection == doc { selection = nil }
                context.delete(doc)
                try? context.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Folder row (recursive)

struct FolderRow: View {
    let folder: NoteFolder
    let roots: [NoteFolder]
    @Binding var selection: StudyDocument?
    @Binding var expanded: Set<PersistentIdentifier>
    @Bindable var drag: DragContext
    let onRename: (NoteFolder) -> Void
    let onNewSubfolder: (NoteFolder) -> Void
    let onDelete: (NoteFolder) -> Void
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
                    expanded: $expanded, drag: drag,
                    onRename: onRename, onNewSubfolder: onNewSubfolder, onDelete: onDelete
                )
            }
            ForEach(folder.sortedDocuments) { doc in
                DocumentRow(doc: doc, roots: roots, selection: $selection, drag: drag)
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
            drag.item = .folder(folder)
            return NSItemProvider(object: folder.name as NSString)
        }
        .onDrop(of: [.text], isTargeted: $targeted) { _ in
            guard let item = drag.item else { return false }
            moveItem(item, to: folder, context: context)
            expanded.insert(folder.persistentModelID)
            drag.item = nil
            return true
        }
        .contextMenu {
            Button { onNewSubfolder(folder) } label: {
                Label("New Subfolder", systemImage: "folder.badge.plus")
            }
            Button { onRename(folder) } label: {
                Label("Rename…", systemImage: "pencil")
            }
            MoveToMenu(item: .folder(folder), roots: roots)
            Divider()
            Button(role: .destructive) { onDelete(folder) } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
}
