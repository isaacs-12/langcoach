import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Extracts text — and, where the source carries it, formatting — from files the
/// user imports. Google Docs can be exported to any of these formats (File ▸
/// Download), so this covers the user's notes.
enum DocumentImporter {

    /// File types the import panel should accept.
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf, .rtf, .html]
        // .docx / .doc
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        // Markdown
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        return types
    }

    /// File extensions the folder scanner should pick up. Kept in sync with the
    /// `extract(from:)` switch below.
    static let allowedExtensions: Set<String> = [
        "txt", "text", "md", "markdown",
        "pdf", "rtf", "rtfd",
        "docx", "doc", "html", "htm",
    ]

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

    /// Reads `url` and returns its title, plain text, and — when the source
    /// carries formatting — an RTF representation of that formatting.
    /// `url` should already be inside a security-scoped access block if sandboxed.
    static func extract(from url: URL) throws -> (title: String, text: String, formatted: Data?) {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        let text: String
        var formatted: Data? = nil

        switch ext {
        case "md", "markdown":
            let raw = try readPlainText(url)
            text = raw
            formatted = rtf(fromMarkdown: raw)
        case "txt", "text":
            text = try readPlainText(url)
        case "pdf":
            text = try readPDF(url)
        case "rtf", "rtfd":
            (text, formatted) = try readAttributed(url, type: .rtf)
        case "docx":
            (text, formatted) = try readAttributed(url, type: .officeOpenXML)
        case "doc":
            (text, formatted) = try readAttributed(url, type: .docFormat)
        case "html", "htm":
            (text, formatted) = try readAttributed(url, type: .html)
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
        return (title, cleaned, formatted)
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

    /// Reads an attributed document and returns both its plain text and an RTF
    /// serialization of its formatting.
    private static func readAttributed(_ url: URL, type: NSAttributedString.DocumentType) throws -> (String, Data?) {
        let data = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        let attr = try NSAttributedString(data: data, options: options, documentAttributes: nil)
        return (attr.string, rtf(from: attr))
    }

    /// Serializes an attributed string to RTF data (nil on failure / empty).
    private static func rtf(from attr: NSAttributedString) -> Data? {
        guard attr.length > 0 else { return nil }
        return try? attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Parses Markdown into an attributed string and serializes it to RTF so that
    /// inline emphasis (bold/italic/links) survives into the viewer.
    private static func rtf(fromMarkdown raw: String) -> Data? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let parsed = try? AttributedString(markdown: raw, options: options) else { return nil }
        return rtf(from: NSAttributedString(parsed))
    }
}
