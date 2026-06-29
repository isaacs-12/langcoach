import SwiftUI
import SwiftData

struct FlashcardsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var selectedDeck: Deck?
    @State private var studying: Deck?
    @State private var addingCard = false
    @State private var creatingDeck = false
    @State private var newDeckName = ""

    var body: some View {
        Group {
            if decks.isEmpty {
                CalloutView(
                    systemImage: "rectangle.on.rectangle.angled",
                    title: "No decks yet",
                    message: "Create a deck and add cards by hand, or go to Library and let the AI pull vocabulary straight from your notes.",
                    actionTitle: "New deck",
                    action: { creatingDeck = true }
                )
            } else {
                HSplitView {
                    deckList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    deckDetail
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Flashcards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingDeck = true } label: {
                    Label("New deck", systemImage: "plus")
                }
            }
        }
        .sheet(item: $studying) { deck in
            StudySessionView(deck: deck)
        }
        .sheet(isPresented: $addingCard) {
            if let deck = selectedDeck {
                CardEditorView(deck: deck)
            }
        }
        .alert("New deck", isPresented: $creatingDeck) {
            TextField("Deck name", text: $newDeckName)
            Button("Create") { createDeck() }
            Button("Cancel", role: .cancel) { newDeckName = "" }
        }
    }

    private var deckList: some View {
        List(selection: $selectedDeck) {
            ForEach(decks) { deck in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deck.name).font(.body.weight(.medium))
                        Text("\(deck.cards.count) cards")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if deck.dueCount > 0 {
                        Text("\(deck.dueCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                .padding(.vertical, 3)
                .tag(deck)
                .contextMenu {
                    Button(role: .destructive) { delete(deck) } label: {
                        Label("Delete deck", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deckDetail: some View {
        if let deck = selectedDeck ?? decks.first {
            DeckDetailView(deck: deck,
                           onStudy: { studying = deck },
                           onAddCard: { selectedDeck = deck; addingCard = true })
        } else {
            CalloutView(systemImage: "rectangle.stack",
                        title: "Select a deck",
                        message: "Choose a deck to study or manage its cards.")
        }
    }

    private func createDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let deck = Deck(name: name)
        context.insert(deck)
        try? context.save()
        selectedDeck = deck
        newDeckName = ""
    }

    private func delete(_ deck: Deck) {
        if selectedDeck == deck { selectedDeck = nil }
        context.delete(deck)
        try? context.save()
    }
}

// MARK: - Deck detail

private struct DeckDetailView: View {
    @Bindable var deck: Deck
    var onStudy: () -> Void
    var onAddCard: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deck.name).font(.title2.bold())
                        if !deck.detail.isEmpty {
                            Text(deck.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    StatBadge(value: "\(deck.dueCount)", label: "Due", tint: Theme.accent)
                    StatBadge(value: "\(deck.newCount)", label: "New", tint: Theme.accentSoft)
                    StatBadge(value: "\(deck.cards.count)", label: "Total", tint: .secondary)
                    Spacer()
                    Button(action: onAddCard) { Label("Add card", systemImage: "plus") }
                        .buttonStyle(.bordered)
                    Button(action: onStudy) { Label("Study", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(deck.cards.isEmpty)
                }
            }
            .padding()
            Divider()
            cardTable
        }
    }

    @ViewBuilder
    private var cardTable: some View {
        if deck.cards.isEmpty {
            CalloutView(systemImage: "plus.rectangle.on.rectangle",
                        title: "No cards in this deck",
                        message: "Add cards manually, or extract them from a note in your Library.",
                        actionTitle: "Add a card", action: onAddCard)
        } else {
            List {
                ForEach(deck.cards.sorted(by: { $0.createdAt > $1.createdAt })) { card in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.korean).font(.body.weight(.medium))
                            Text(card.english).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if card.isNew {
                            Text("new").font(.caption2)
                                .foregroundStyle(Theme.accentSoft)
                        } else {
                            Text("due \(card.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(card)
                            try? context.save()
                        } label: { Label("Delete card", systemImage: "trash") }
                    }
                }
            }
        }
    }
}
