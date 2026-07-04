import SwiftUI
import AppKit

/// Read-only rich-text viewer backed by `NSTextView`. Renders the RTF stored on a
/// `StudyDocument` (`formattedData`) so the source formatting — bold, italics,
/// headings, lists — is preserved on screen. It manages its own scrolling, so it
/// should not be nested inside a SwiftUI `ScrollView`.
///
/// Imported RTF usually hard-codes near-black body text, which is unreadable on a
/// dark window. `normalize` remaps that default body color to the adaptive
/// `.labelColor` (keeping genuinely colored highlights) and optionally scales the
/// font — so the same note reads well in light and dark mode and at any text size.
struct RichTextView: NSViewRepresentable {
    let data: Data
    /// Multiplies every font size, for the reader's text-size controls.
    var fontScale: CGFloat = 1
    /// Draw a solid document-like background (`.textBackgroundColor`) instead of
    /// letting the window color show through. Gives the note a "paper" surface.
    var paper: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 20, height: 20)
        // Wrap to the view width rather than scrolling horizontally.
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        configureBackground(scrollView, textView)
        apply(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        configureBackground(scrollView, textView)
        apply(to: textView)
    }

    private func configureBackground(_ scrollView: NSScrollView, _ textView: NSTextView) {
        scrollView.drawsBackground = paper
        scrollView.backgroundColor = paper ? .textBackgroundColor : .clear
        textView.drawsBackground = paper
        textView.backgroundColor = paper ? .textBackgroundColor : .clear
    }

    private func apply(to textView: NSTextView) {
        guard let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return }
        textView.textStorage?.setAttributedString(normalize(attr))
    }

    /// Remap default body text to the adaptive label color and scale fonts.
    private func normalize(_ attr: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: m.length)

        m.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if isBodyColor(value as? NSColor) {
                m.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }

        if fontScale != 1 {
            m.enumerateAttribute(.font, in: full) { value, range, _ in
                guard let font = value as? NSFont else { return }
                let scaled = NSFontManager.shared.convert(font, toSize: font.pointSize * fontScale)
                m.addAttribute(.font, value: scaled, range: range)
            }
        }
        return m
    }

    /// True when a run's color is missing or a near-black / low-saturation gray —
    /// i.e. ordinary body text that should follow the system label color rather
    /// than staying black on a dark background. Saturated or bright colors (real
    /// highlights) are left untouched.
    private func isBodyColor(_ color: NSColor?) -> Bool {
        guard let color else { return true }
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return true }
        return rgb.saturationComponent < 0.15 && rgb.brightnessComponent < 0.4
    }
}
