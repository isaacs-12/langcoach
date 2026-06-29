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

    init(title: String, sourceFilename: String, text: String, importedAt: Date = .now, studyMemory: String = "") {
        self.title = title
        self.sourceFilename = sourceFilename
        self.text = text
        self.importedAt = importedAt
        self.studyMemory = studyMemory
    }

    /// Whether a distilled study memory is available for practice context.
    var hasMemory: Bool {
        !studyMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
