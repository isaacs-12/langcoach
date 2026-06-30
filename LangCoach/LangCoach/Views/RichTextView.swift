import SwiftUI
import AppKit

/// Read-only rich-text viewer backed by `NSTextView`. Renders the RTF stored on a
/// `StudyDocument` (`formattedData`) so the source formatting — bold, italics,
/// headings, lists — is preserved on screen. It manages its own scrolling, so it
/// should not be nested inside a SwiftUI `ScrollView`.
struct RichTextView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        // Wrap to the view width rather than scrolling horizontally.
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        apply(data: data, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        apply(data: data, to: textView)
    }

    private func apply(data: Data, to textView: NSTextView) {
        guard let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return }
        textView.textStorage?.setAttributedString(attr)
    }
}
