import SwiftUI
import SwiftData
import AppKit

/// The state of a single word's dictionary lookup.
enum LookupState {
    case loading
    case loaded(WordDefinition)
    case failed(String)
}

/// Which practice screen a tapped word came from — determines the name of the
/// dated deck a saved flashcard lands in.
enum PracticeSource {
    case conversation
    case translation

    var deckPrefix: String {
        switch self {
        case .conversation: return "Conversation practice"
        case .translation:  return "Translation practice"
        }
    }

    /// The deck name for a given day, e.g. "Conversation practice Jul 3, 2026".
    /// Uses a fixed (locale-independent) format so every session on the same date
    /// resolves to the exact same name — no duplicate decks.
    func deckName(on date: Date) -> String {
        "\(deckPrefix) \(Self.dayFormatter.string(from: date))"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

/// Renders Korean text as a run of individually tappable words. Double-clicking a
/// word asks the coach for its dictionary form + meaning (context-aware) and shows
/// the result in a popover anchored to that word. Hovering highlights the word so
/// the interaction is discoverable.
///
/// This replaces `.textSelection(.enabled)` on the Korean it renders — for a study
/// app, tapping to look a word up is the more valuable gesture; a right-click
/// "Copy" keeps copy available.
struct TappableKoreanText: View {
    let text: String
    /// The practice screen this text lives on, so a saved word goes to the right
    /// dated deck. When nil, the "Add to flashcards" action is hidden.
    var source: PracticeSource? = nil
    @Environment(Coach.self) private var coach
    @Environment(\.modelContext) private var modelContext

    @State private var openIndex: Int?
    @State private var hoverIndex: Int?
    @State private var lookups: [Int: LookupState] = [:]
    /// Token indices already saved as a flashcard this session (for popover state).
    @State private var savedIndices: Set<Int> = []

    /// Whitespace-separated tokens, kept with their punctuation for display.
    private var tokens: [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                wordView(token, index)
            }
        }
        .help("Double-click a word to see its dictionary form and meaning")
    }

    @ViewBuilder
    private func wordView(_ token: String, _ index: Int) -> some View {
        let clean = Self.core(token)
        let interactive = !clean.isEmpty
        let active = hoverIndex == index || openIndex == index

        Text(token)
            .padding(.horizontal, 2)
            .background(
                active ? Theme.accent.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { inside in
                guard interactive else { return }
                if inside {
                    hoverIndex = index
                    NSCursor.pointingHand.set()
                } else {
                    if hoverIndex == index { hoverIndex = nil }
                    NSCursor.arrow.set()
                }
            }
            .onTapGesture(count: 2) {
                guard interactive else { return }
                openIndex = index
                lookUp(clean, at: index)
            }
            .popover(isPresented: binding(for: index), arrowEdge: .bottom) {
                WordDefinitionPopover(
                    word: clean,
                    state: lookups[index] ?? .loading,
                    canSave: source != nil,
                    isSaved: savedIndices.contains(index),
                    onSave: { def in
                        saveFlashcard(def, tappedWord: clean)
                        savedIndices.insert(index)
                    }
                )
            }
            .contextMenu {
                Button("Copy") { copy(token) }
                Button("Copy message") { copy(text) }
            }
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { openIndex == index },
            set: { shown in if !shown, openIndex == index { openIndex = nil } }
        )
    }

    private func lookUp(_ word: String, at index: Int) {
        // Cache: a word that already resolved doesn't need a second round-trip.
        if case .loaded = lookups[index] { return }
        lookups[index] = .loading
        let sentence = text
        Task {
            do {
                let def = try await coach.defineWord(word, in: sentence)
                await MainActor.run { lookups[index] = .loaded(def) }
            } catch {
                await MainActor.run { lookups[index] = .failed(error.localizedDescription) }
            }
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// Saves a looked-up word as a flashcard in today's practice deck, creating
    /// that deck once and reusing it for every later save on the same date.
    /// Skips silently if the same word is already in the deck (no duplicates).
    private func saveFlashcard(_ def: WordDefinition, tappedWord: String) {
        guard let source else { return }
        let korean = def.dictionaryForm.isEmpty ? tappedWord : def.dictionaryForm
        guard !korean.isEmpty else { return }

        let deck = practiceDeck(for: source)
        if deck.cards.contains(where: { $0.korean == korean }) { return }

        let card = Flashcard(
            korean: korean,
            english: def.meaning,
            reading: def.reading,
            example: text,
            notes: def.note,
            deck: deck
        )
        modelContext.insert(card)
        try? modelContext.save()
    }

    /// Finds today's dated deck for this practice source, or creates it. Fetching
    /// by exact name guarantees a single deck per (source, day) across sessions.
    private func practiceDeck(for source: PracticeSource) -> Deck {
        let name = source.deckName(on: Date())
        var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let deck = Deck(name: name, detail: "Saved while practicing")
        modelContext.insert(deck)
        return deck
    }

    /// Strips leading/trailing punctuation so "먹었어요?" looks up as "먹었어요".
    private static func core(_ w: String) -> String {
        w.trimmingCharacters(in: CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines))
    }
}

/// The card shown when a word is tapped: dictionary form, part of speech, reading,
/// meaning, and a usage note — or a loading / error state.
struct WordDefinitionPopover: View {
    let word: String
    let state: LookupState
    /// Whether this text supports saving words as flashcards.
    var canSave: Bool = false
    /// Whether this word has already been saved (shows a confirmed state).
    var isSaved: Bool = false
    var onSave: ((WordDefinition) -> Void)? = nil

    var body: some View {
        Group {
            switch state {
            case .loading: loadingView
            case .loaded(let def): loadedView(def)
            case .failed(let message): failedView(message)
            }
        }
        .padding(16)
        .frame(width: 264, alignment: .leading)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline(word)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking up…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadedView(_ def: WordDefinition) -> some View {
        let root = def.dictionaryForm.isEmpty ? word : def.dictionaryForm
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                headline(root)
                if !def.partOfSpeech.isEmpty {
                    Text(def.partOfSpeech)
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 2).padding(.horizontal, 7)
                        .background(Theme.accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }

            if !def.reading.isEmpty {
                Text(def.reading)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }

            // Show the origin only when the tapped form differs from the root.
            if root != word {
                (Text(Image(systemName: "arrow.turn.down.right")) + Text("  from ") + Text(word).fontWeight(.medium))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            if !def.meaning.isEmpty {
                Text(def.meaning)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !def.note.isEmpty {
                Text(def.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canSave, let onSave {
                Divider()
                Button {
                    if !isSaved { onSave(def) }
                } label: {
                    Label(
                        isSaved ? "Added to flashcards" : "Add to flashcards",
                        systemImage: isSaved ? "checkmark.circle.fill" : "plus.circle"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isSaved ? Theme.success : Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headline(word)
            Label("Couldn't look this up", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headline(_ s: String) -> some View {
        Text(s)
            .font(.title2.bold())
            .foregroundStyle(Theme.brandGradient)
    }
}
