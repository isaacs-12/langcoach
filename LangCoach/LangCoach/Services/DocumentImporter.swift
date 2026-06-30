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
        // Google Docs shortcut (.gdoc) — registered by Drive for Desktop, but
        // fall back to a filename-extension type so it's accepted even if the
        // declared type isn't on this machine.
        if let gdoc = UTType("com.google.gdoc") ?? UTType(filenameExtension: "gdoc") { types.append(gdoc) }
        return types
    }

    /// File extensions the folder scanner should pick up. Kept in sync with the
    /// `extract(from:)` / `load(from:)` switches below.
    static let allowedExtensions: Set<String> = [
        "txt", "text", "md", "markdown",
        "pdf", "rtf", "rtfd",
        "docx", "doc", "html", "htm",
        "gdoc",
    ]

    enum ImportError: LocalizedError {
        case unsupported(String)
        case unreadable(String)
        case googleDocUnshared(String)
        case googleDocFetchFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "Unsupported file type: .\(ext)"
            case .unreadable(let name): return "Could not read text from \(name)"
            case .googleDocUnshared(let name):
                return "“\(name)” is a private Google Doc, so its text isn't stored on your Mac — the .gdoc file is just a link. Sign in to Google to import private docs, or in Drive set “Anyone with the link” to Viewer and re-import."
            case .googleDocFetchFailed(let name):
                return "Couldn't fetch “\(name)” from Google Drive. Make sure you're signed in to the account that owns it and the doc still exists."
            }
        }
    }

    /// Network-aware entry point. Handles `.gdoc` shortcuts (which carry no text
    /// locally and must be fetched from Google) and otherwise delegates to the
    /// synchronous `extract(from:)`. Runs on the main actor because the underlying
    /// attributed-string (HTML/RTF) parsing is not thread-safe.
    ///
    /// `url` should already be inside a security-scoped access block if sandboxed.
    /// `googleToken` is a Google Drive access token used to fetch `.gdoc`
    /// shortcuts; when present, private docs work too. Pass nil to fall back to the
    /// unauthenticated best-effort fetch (link-shared docs only).
    @MainActor
    static func load(from url: URL, googleToken: String? = nil) async throws -> (title: String, text: String, formatted: Data?) {
        if url.pathExtension.lowercased() == "gdoc" {
            return try await loadGoogleDoc(url, token: googleToken)
        }
        return try extract(from: url)
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

    // MARK: - Google Docs (.gdoc shortcuts)

    /// Resolve a `.gdoc` shortcut into text. The on-disk file is only a JSON
    /// pointer (`{ "doc_id": …, "url": … }`), so we read the id locally and fetch
    /// the document from Google. With a Drive `token` we use the authenticated
    /// Drive API (private docs work); without one we fall back to the public
    /// export endpoint (link-shared docs only).
    @MainActor
    private static func loadGoogleDoc(_ url: URL, token: String?) async throws -> (title: String, text: String, formatted: Data?) {
        let title = url.deletingPathExtension().lastPathComponent
        let stub = try Data(contentsOf: url)
        guard let docId = googleDocId(from: stub) else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        if let token {
            return try await exportViaDriveAPI(docId: docId, title: title, token: token)
        }
        return try await exportViaPublicLink(docId: docId, title: title)
    }

    /// Authenticated export through the Drive API — works for any doc the signed-in
    /// account can read, including private ones.
    @MainActor
    private static func exportViaDriveAPI(docId: String, title: String, token: String) async throws -> (title: String, text: String, formatted: Data?) {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(docId)/export")!
        components.queryItems = [URLQueryItem(name: "mimeType", value: "text/html")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ImportError.googleDocFetchFailed(title)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ImportError.googleDocFetchFailed(title)
        }
        return try parseGoogleHTML(data, title: title)
    }

    /// Unauthenticated best-effort export. A private doc redirects through
    /// accounts.google.com to a sign-in page that still returns 200/HTML, so a
    /// status check alone isn't enough — the final host tells us whether we landed
    /// on the doc or the login wall.
    @MainActor
    private static func exportViaPublicLink(docId: String, title: String) async throws -> (title: String, text: String, formatted: Data?) {
        guard let exportURL = URL(string: "https://docs.google.com/document/d/\(docId)/export?format=html") else {
            throw ImportError.unreadable(title)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: exportURL)
        } catch {
            throw ImportError.googleDocUnshared(title)
        }
        if let host = response.url?.host, host.contains("accounts.google.com") {
            throw ImportError.googleDocUnshared(title)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ImportError.googleDocUnshared(title)
        }
        return try parseGoogleHTML(data, title: title)
    }

    private static func parseGoogleHTML(_ data: Data, title: String) throws -> (title: String, text: String, formatted: Data?) {
        let (text, formatted) = try attributed(from: data, type: .html)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ImportError.unreadable(title) }
        return (title, cleaned, formatted)
    }

    /// Pull the document id out of a `.gdoc` stub's JSON — preferring the explicit
    /// `doc_id`, falling back to the `id` query item in its `url`.
    private static func googleDocId(from stub: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: stub) as? [String: Any] else { return nil }
        if let id = json["doc_id"] as? String, !id.isEmpty { return id }
        if let urlString = json["url"] as? String,
           let components = URLComponents(string: urlString),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            return id
        }
        return nil
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
        try attributed(from: try Data(contentsOf: url), type: type)
    }

    /// Parses `data` of the given document type into plain text plus an RTF
    /// serialization of its formatting.
    private static func attributed(from data: Data, type: NSAttributedString.DocumentType) throws -> (String, Data?) {
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
