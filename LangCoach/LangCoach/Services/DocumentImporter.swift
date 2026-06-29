import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Extracts plain text from files the user imports. Google Docs can be exported
/// to any of these formats (File ▸ Download), so this covers the user's notes.
enum DocumentImporter {

    /// File types the import panel should accept.
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf, .rtf]
        // .docx / .doc
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        // Markdown
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        return types
    }

    enum ImportError: LocalizedError {
        case unsupported(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "Unsupported file type: .\(ext)"
            case .unreadable(let name): return "Could not read text from \(name)"
            }
        }
    }

    /// Reads `url` and returns its title + extracted plain text.
    /// `url` should already be inside a security-scoped access block if sandboxed.
    static func extract(from url: URL) throws -> (title: String, text: String) {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        let text: String

        switch ext {
        case "txt", "md", "markdown", "text":
            text = try readPlainText(url)
        case "pdf":
            text = try readPDF(url)
        case "rtf", "rtfd":
            text = try readAttributed(url, type: .rtf)
        case "docx":
            text = try readAttributed(url, type: .officeOpenXML)
        case "doc":
            text = try readAttributed(url, type: .docFormat)
        case "html", "htm":
            text = try readAttributed(url, type: .html)
        default:
            // Last-ditch attempt: treat as plain text.
            if let t = try? readPlainText(url), !t.isEmpty {
                text = t
            } else {
                throw ImportError.unsupported(ext)
            }
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ImportError.unreadable(url.lastPathComponent) }
        return (title, cleaned)
    }

    // MARK: - Readers

    private static func readPlainText(_ url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        // Fall back to lenient encoding detection.
        var usedEncoding: String.Encoding = .utf8
        return try String(contentsOf: url, usedEncoding: &usedEncoding)
    }

    private static func readPDF(_ url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        var pages: [String] = []
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let s = page.string {
                pages.append(s)
            }
        }
        return pages.joined(separator: "\n\n")
    }

    private static func readAttributed(_ url: URL, type: NSAttributedString.DocumentType) throws -> String {
        let data = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        let attr = try NSAttributedString(data: data, options: options, documentAttributes: nil)
        return attr.string
    }
}
