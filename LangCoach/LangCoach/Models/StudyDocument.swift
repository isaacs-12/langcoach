import Foundation
import SwiftData

/// A class note imported from the user's file system (e.g. a Google Doc exported
/// to .docx / .pdf / .txt). The extracted plain text is stored locally so the app
/// works fully offline once imported.
@Model
final class StudyDocument {
    var title: String
    var sourceFilename: String
    var text: String
    var importedAt: Date
    /// A compact distilled summary (key vocab, grammar, themes) produced once at
    /// import time. Reused as practice context so the full note text never has to
    /// be sent to the model again. Empty until distillation succeeds.
    var studyMemory: String = ""
    /// RTF data preserving the source formatting (bold, italics, headings, …).
    /// Nil when the source carried no usable formatting (plain text / PDF), in
    /// which case the viewer falls back to rendering `text`.
    var formattedData: Data? = nil
    /// Absolute path of the source file when this note came from a mounted notes
    /// folder. Empty for notes added one-off via the import panel. Used to keep
    /// folder contents in sync without creating duplicates.
    var sourcePath: String = ""
    /// File content-modification date at the last import, used to detect when a
    /// mounted file has changed and needs re-importing.
    var sourceModified: Date? = nil
    /// The folder this note is filed under, or nil for top-level notes. Assigned
    /// once (mirrored from disk on folder sync, or chosen by the user); manual
    /// moves are preserved across re-syncs. Inverse of `NoteFolder.documents`.
    var folder: NoteFolder? = nil

    init(title: String, sourceFilename: String, text: String, importedAt: Date = .now, studyMemory: String = "", formattedData: Data? = nil, sourcePath: String = "", sourceModified: Date? = nil, folder: NoteFolder? = nil) {
        self.title = title
        self.sourceFilename = sourceFilename
        self.text = text
        self.importedAt = importedAt
        self.studyMemory = studyMemory
        self.formattedData = formattedData
        self.sourcePath = sourcePath
        self.sourceModified = sourceModified
        self.folder = folder
    }

    /// Whether a distilled study memory is available for practice context.
    var hasMemory: Bool {
        !studyMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The lesson's practice themes, parsed from the `THEMES:` line of the
    /// distilled study memory (see `Coach.distillNotes`). These drive the tappable
    /// topic suggestions in conversation practice, so the same lesson themes can be
    /// practiced again and again. Empty when no memory exists or none were listed.
    var themes: [String] {
        guard hasMemory else { return [] }
        // Tolerate markdown/list decoration the model sometimes adds despite the
        // plain-text instruction (e.g. "**THEMES:**", "## THEMES", "- Themes:").
        let decoration = CharacterSet(charactersIn: " \t*#->•")
        for line in studyMemory.split(whereSeparator: \.isNewline) {
            let cleaned = line.trimmingCharacters(in: decoration)
            guard let range = cleaned.range(of: "THEMES", options: [.caseInsensitive, .anchored])
            else { continue }
            let list = cleaned[range.upperBound...].drop { $0 == ":" || $0 == "*" || $0 == " " }
            return list
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " *_")) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    /// A short preview of the document body for list display.
    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(160))
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }
}
