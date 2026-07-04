import SwiftUI
import SwiftData

/// A dedicated, full-window reader for a single note. Opened from the Library
/// (double-click a note, the "Open" button, or the row's context menu), it
/// presents the note on a paper-like surface with adjustable text size — far more
/// comfortable than the cramped, gray-backgrounded inline preview in the sidebar.
///
/// The note is looked up by its `PersistentIdentifier` (the value the reader
/// `WindowGroup` is keyed on) so the same note reuses its window instead of piling
/// up duplicates. `StudyDocument` is a `@Model`, so reading its properties here
/// keeps the reader in sync with edits made elsewhere (e.g. distillation).
struct NoteReaderView: View {
    let documentID: PersistentIdentifier

    @Environment(\.modelContext) private var context
    @State private var fontScale: CGFloat = 1
    @State private var showMemory = true
    @State private var extracting = false

    private static let minScale: CGFloat = 0.7
    private static let maxScale: CGFloat = 2.2

    private var doc: StudyDocument? {
        context.model(for: documentID) as? StudyDocument
    }

    var body: some View {
        Group {
            if let doc {
                reader(doc)
            } else {
                CalloutView(
                    systemImage: "doc.questionmark",
                    title: "Note unavailable",
                    message: "This note may have been deleted from your library."
                )
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private func reader(_ doc: StudyDocument) -> some View {
        VStack(spacing: 0) {
            if showMemory, doc.hasMemory {
                memoryBanner(doc)
                Divider()
            }
            body(doc)
        }
        .navigationTitle(doc.title)
        .navigationSubtitle("\(doc.wordCount) words")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if doc.hasMemory {
                    Button {
                        showMemory.toggle()
                    } label: {
                        Label("Study memory", systemImage: showMemory ? "brain.head.profile" : "brain")
                    }
                    .help(showMemory ? "Hide the distilled study memory" : "Show the distilled study memory")
                }
                fontControls
                Button {
                    extracting = true
                } label: {
                    Label("Extract vocab", systemImage: "sparkles")
                }
                .help("Pull vocabulary from this note into a flashcard deck")
            }
        }
        .sheet(isPresented: $extracting) {
            VocabExtractionSheet(document: doc)
        }
    }

    private var fontControls: some View {
        ControlGroup {
            Button {
                fontScale = max(Self.minScale, fontScale - 0.1)
            } label: {
                Label("Smaller text", systemImage: "textformat.size.smaller")
            }
            .disabled(fontScale <= Self.minScale)

            Button {
                fontScale = min(Self.maxScale, fontScale + 0.1)
            } label: {
                Label("Larger text", systemImage: "textformat.size.larger")
            }
            .disabled(fontScale >= Self.maxScale)
        }
        .help("Adjust the reading text size")
    }

    // MARK: - Body

    @ViewBuilder
    private func body(_ doc: StudyDocument) -> some View {
        if let data = doc.formattedData {
            RichTextView(data: data, fontScale: fontScale, paper: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Plain-text note: mirror the rich-text reader's paper surface and
            // adaptive text so it reads the same way at any size.
            ScrollView {
                Text(doc.text)
                    .font(.system(size: 15 * fontScale))
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Study memory

    private func memoryBanner(_ doc: StudyDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Study memory", systemImage: "brain.head.profile")
                .font(.headline)
                .foregroundStyle(Theme.accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(doc.studyMemory)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !doc.themes.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(doc.themes, id: \.self) { theme in
                                Text(theme)
                                    .font(.caption.weight(.medium))
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 10)
                                    .background(Theme.accent.opacity(0.14), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding()
        .frame(maxHeight: 200)
        .background(Theme.accent.opacity(0.06))
    }
}
