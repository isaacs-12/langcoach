import SwiftUI
import SwiftData

struct VocabExtractionSheet: View {
    let document: StudyDocument

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Coach.self) private var coach
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var phase: Phase = .idle
    @State private var items: [SelectableVocab] = []
    @State private var errorMessage: String?

    @State private var deckChoice: DeckChoice = .new
    @State private var newDeckName: String = ""
    @State private var existingDeck: Deck?

    enum Phase { case idle, loading, review }
    enum DeckChoice: Hashable { case new, existing }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .onAppear {
            newDeckName = document.title
            if phase == .idle { extract() }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(Theme.brandGradient)
            VStack(alignment: .leading, spacing: 1) {
                Text("Extract vocabulary").font(.headline)
                Text(document.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            VStack(spacing: 14) {
                ProgressView()
                Text("Reading your notes and pulling out useful vocabulary…")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .review:
            if let errorMessage {
                CalloutView(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't extract vocab",
                    message: errorMessage,
                    actionTitle: "Try again",
                    action: { extract() }
                )
            } else if items.isEmpty {
                CalloutView(
                    systemImage: "questionmark.text.page",
                    title: "No vocabulary found",
                    message: "The model didn't find Korean vocabulary in this note. Try a different document."
                )
            } else {
                reviewList
            }
        }
    }

    private var reviewList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(selectedCount) of \(items.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(allSelected ? "Deselect all" : "Select all") {
                    let target = !allSelected
                    for i in items.indices { items[i].selected = target }
                }
                .buttonStyle(.link)
            }
            .padding(.horizontal).padding(.vertical, 8)

            List {
                ForEach($items) { $item in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: $item.selected)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.vocab.korean).font(.body.weight(.semibold))
                                if !item.vocab.reading.isEmpty {
                                    Text(item.vocab.reading)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(item.vocab.english).font(.callout).foregroundStyle(.secondary)
                            if !item.vocab.example.isEmpty {
                                Text(item.vocab.example)
                                    .font(.caption).foregroundStyle(.tertiary).italic()
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if phase == .review && !items.isEmpty {
                Picker("Save to", selection: $deckChoice) {
                    Text("New deck").tag(DeckChoice.new)
                    Text("Existing").tag(DeckChoice.existing)
                        .disabled(decks.isEmpty)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                if deckChoice == .new {
                    TextField("Deck name", text: $newDeckName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                } else {
                    Picker("", selection: $existingDeck) {
                        Text("Choose…").tag(Optional<Deck>.none)
                        ForEach(decks) { d in Text(d.name).tag(Optional(d)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save \(selectedCount) card\(selectedCount == 1 ? "" : "s")") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding()
    }

    // MARK: - Derived

    private var selectedCount: Int { items.filter(\.selected).count }
    private var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.selected) }
    private var canSave: Bool {
        guard phase == .review, selectedCount > 0 else { return false }
        switch deckChoice {
        case .new: return !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty
        case .existing: return existingDeck != nil
        }
    }

    // MARK: - Actions

    private func extract() {
        phase = .loading
        errorMessage = nil
        Task {
            do {
                let result = try await coach.extractVocab(from: document.text)
                await MainActor.run {
                    items = result.map { SelectableVocab(vocab: $0, selected: true) }
                    phase = .review
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .review
                }
            }
        }
    }

    private func save() {
        let deck: Deck
        switch deckChoice {
        case .new:
            deck = Deck(name: newDeckName.trimmingCharacters(in: .whitespaces),
                        detail: "From \(document.title)")
            context.insert(deck)
        case .existing:
            guard let existingDeck else { return }
            deck = existingDeck
        }
        for item in items where item.selected {
            let card = Flashcard(
                korean: item.vocab.korean,
                english: item.vocab.english,
                reading: item.vocab.reading,
                example: item.vocab.example,
                deck: deck
            )
            context.insert(card)
        }
        try? context.save()
        dismiss()
    }
}

struct SelectableVocab: Identifiable {
    let id = UUID()
    var vocab: ExtractedVocab
    var selected: Bool
}
