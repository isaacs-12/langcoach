import Foundation
import SwiftData

/// A folder for organizing `StudyDocument`s. Folders nest arbitrarily via the
/// self-referential `parent`/`children` relationship, and a note belongs to at
/// most one folder (notes with no folder live at the top level).
///
/// Folders come from two sources that share this one model:
/// - **Mirrored** from a linked notes folder's subdirectories (`sourcePath` set).
/// - **Hand-made** by the user (`sourcePath` empty).
@Model
final class NoteFolder {
    var name: String
    var createdAt: Date
    /// Absolute path of the source directory when this folder mirrors a
    /// subdirectory of a mounted notes folder. Empty for user-created folders.
    /// Used to find-or-create the matching folder on sync without duplicating.
    var sourcePath: String = ""

    /// Parent folder, or nil when this is a top-level folder.
    var parent: NoteFolder? = nil

    /// Child folders. Deleting a folder deletes its subfolders; the notes inside
    /// are preserved (their `folder` is nullified, moving them to the top level).
    @Relationship(deleteRule: .cascade, inverse: \NoteFolder.parent)
    var children: [NoteFolder] = []

    /// Notes filed directly under this folder.
    @Relationship(inverse: \StudyDocument.folder)
    var documents: [StudyDocument] = []

    init(name: String, createdAt: Date = .now, sourcePath: String = "", parent: NoteFolder? = nil) {
        self.name = name
        self.createdAt = createdAt
        self.sourcePath = sourcePath
        self.parent = parent
    }

    /// Whether `other` is this folder or one of its descendants — used to reject
    /// moves that would create a cycle.
    func contains(_ other: NoteFolder) -> Bool {
        var node: NoteFolder? = other
        while let current = node {
            if current === self { return true }
            node = current.parent
        }
        return false
    }
}
