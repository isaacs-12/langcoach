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

    init(title: String, sourceFilename: String, text: String, importedAt: Date = .now) {
        self.title = title
        self.sourceFilename = sourceFilename
        self.text = text
        self.importedAt = importedAt
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
