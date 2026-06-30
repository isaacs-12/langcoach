import SwiftUI
import SwiftData

/// Sidebar selection: a single deck, or the cross-deck "All Decks" pool.
private enum DeckSelection: Hashable {
    case all
    case deck(Deck)
}

struct FlashcardsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var selection: DeckSelection? = .all
    @State private var studying: StudyRequest?
    @State private var addingCard = false
    @State private var addCardDeck: Deck?
    @State private var creatingDeck = false
    @State private var newDeckName = ""

    /// Every card across every deck — the pool for cross-set study.
    private var allCards: [Flashcard] { decks.flatMap(\.cards) }

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
        .sheet(item: $studying) { request in
            StudySessionView(title: request.title, cards: request.cards)
        }
        .sheet(isPresented: $addingCard) {
            if let deck = addCardDeck {
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
        List(selection: $selection) {
            Section {
                HStack {
                    Label("All Decks", systemImage: "square.stack.3d.up")
                        .font(.body.weight(.medium))
                    Spacer()
                    let starred = allCards.lazy.filter(\.isStarred).count
                    if starred > 0 {
                        Label("\(starred)", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                    }
                }
                .padding(.vertical, 3)
                .tag(DeckSelection.all)
            }
            Section("Decks") {
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
                    .tag(DeckSelection.deck(deck))
                    .contextMenu {
                        Button(role: .destructive) { delete(deck) } label: {
                            Label("Delete deck", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deckDetail: some View {
        switch selection {
        case .all, .none:
            AllDecksDetailView(cards: allCards, onStudy: { studying = $0 })
        case .deck(let deck):
            DeckDetailView(deck: deck,
                           onStudy: { studying = $0 },
                           onAddCard: { addCardDeck = deck; addingCard = true })
        }
    }

    private func createDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let deck = Deck(name: name)
        context.insert(deck)
        try? context.save()
        selection = .deck(deck)
        newDeckName = ""
    }

    private func delete(_ deck: Deck) {
        if selection == .deck(deck) { selection = .all }
        context.delete(deck)
        try? context.save()
    }
}

// MARK: - All-decks detail

/// Cross-set study landing: study all cards or starred cards spanning every deck.
private struct AllDecksDetailView: View {
    let cards: [Flashcard]
    var onStudy: (StudyRequest) -> Void

    @State private var showSetup = false

    private var starredCount: Int { cards.filter(\.isStarred).count }
    private var dueCount: Int { cards.filter(\.isDue).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("All Decks").font(.title2.bold())
                HStack(spacing: 10) {
                    StatBadge(value: "\(dueCount)", label: "Due", tint: Theme.accent)
                    StatBadge(value: "\(starredCount)", label: "Starred", tint: Theme.warning)
                    StatBadge(value: "\(cards.count)", label: "Total", tint: .secondary)
                    Spacer()
                    Button { showSetup = true } label: { Label("Study", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(cards.isEmpty)
                        .popover(isPresented: $showSetup, arrowEdge: .bottom) {
                            StudySetupView(title: "All Decks", pool: cards) { request in
                                showSetup = false
                                onStudy(request)
                            }
                        }
                }
            }
            .padding()
            Divider()
            CalloutView(systemImage: "square.stack.3d.up",
                        title: "Study across all decks",
                        message: "Tap Study to review every card or just your starred cards, in order or shuffled.")
        }
    }
}

// MARK: - Deck detail

private struct DeckDetailView: View {
    @Bindable var deck: Deck
    var onStudy: (StudyRequest) -> Void
    var onAddCard: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showSetup = false

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
                    StatBadge(value: "\(deck.cards.filter(\.isStarred).count)", label: "Starred", tint: Theme.warning)
                    StatBadge(value: "\(deck.cards.count)", label: "Total", tint: .secondary)
                    Spacer()
                    Button(action: onAddCard) { Label("Add card", systemImage: "plus") }
                        .buttonStyle(.bordered)
                    Button { showSetup = true } label: { Label("Study", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(deck.cards.isEmpty)
                        .popover(isPresented: $showSetup, arrowEdge: .bottom) {
                            StudySetupView(title: deck.name, pool: deck.cards) { request in
                                showSetup = false
                                onStudy(request)
                            }
                        }
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
                        Button {
                            card.isStarred.toggle()
                            try? context.save()
                        } label: {
                            Image(systemName: card.isStarred ? "star.fill" : "star")
                                .foregroundStyle(card.isStarred ? Theme.warning : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(card.isStarred ? "Unstar this card" : "Star this card")

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
                        Button {
                            card.isStarred.toggle()
                            try? context.save()
                        } label: {
                            Label(card.isStarred ? "Unstar" : "Star",
                                  systemImage: card.isStarred ? "star.slash" : "star")
                        }
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
