import SwiftUI
import AppKit

/// The state of a single word's dictionary lookup.
enum LookupState {
    case loading
    case loaded(WordDefinition)
    case failed(String)
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
    @Environment(Coach.self) private var coach

    @State private var openIndex: Int?
    @State private var hoverIndex: Int?
    @State private var lookups: [Int: LookupState] = [:]

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
                WordDefinitionPopover(word: clean, state: lookups[index] ?? .loading)
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
