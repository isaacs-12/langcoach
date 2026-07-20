import SwiftUI
import SwiftData

/// A dedicated review window for a single lesson, opened from the Library with
/// `openWindow(id: "lesson-review", value: <persistentModelID>)`. It offers two
/// self-study modes — conversation and translation — both LOCKED to this lesson so
/// practice drills exactly what the lesson taught: the coach steers the chat toward
/// the lesson's grammar, and translation sentences are built from its vocabulary.
///
/// Like the note reader, the lesson is resolved by its `PersistentIdentifier` so
/// re-opening the same lesson reuses its window instead of piling up duplicates.
/// The two modes are mutually exclusive views (switching resets the active one),
/// which keeps each mode's toolbar contributions from colliding in the window bar.
struct TargetedReviewView: View {
    let documentID: PersistentIdentifier

    @Environment(\.modelContext) private var context
    @State private var mode: Mode = .conversation

    enum Mode: String, CaseIterable, Identifiable {
        case conversation, translation
        var id: String { rawValue }
        var label: String { self == .conversation ? "Conversation" : "Translation" }
        var icon: String {
            self == .conversation ? "bubble.left.and.bubble.right.fill" : "character.book.closed.fill"
        }
    }

    private var doc: StudyDocument? {
        context.model(for: documentID) as? StudyDocument
    }

    var body: some View {
        Group {
            if let doc {
                content(doc)
            } else {
                CalloutView(
                    systemImage: "doc.questionmark",
                    title: "Lesson unavailable",
                    message: "This note may have been deleted from your library."
                )
            }
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    @ViewBuilder
    private func content(_ doc: StudyDocument) -> some View {
        VStack(spacing: 0) {
            header(doc)
            Divider()
            switch mode {
            case .conversation:
                ConversationView(lesson: doc)
                    .id("conversation") // fresh state per mode switch
            case .translation:
                TranslateView(lesson: doc)
                    .id("translation")
            }
        }
    }

    private func header(_ doc: StudyDocument) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Reviewing")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(doc.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Label(m.label, systemImage: m.icon).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
