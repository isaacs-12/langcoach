import Foundation
import SwiftData

/// A named collection of flashcards (e.g. "Lesson 12 vocab", "Verbs").
@Model
final class Deck {
    var name: String
    var detail: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Flashcard.deck)
    var cards: [Flashcard] = []

    init(name: String, detail: String = "", createdAt: Date = .now) {
        self.name = name
        self.detail = detail
        self.createdAt = createdAt
    }

    /// Cards that are due for review right now.
    func dueCards(asOf date: Date = .now) -> [Flashcard] {
        cards.filter { $0.dueDate <= date }.sorted { $0.dueDate < $1.dueDate }
    }

    var newCount: Int { cards.filter { $0.reps == 0 }.count }
    var dueCount: Int { dueCards().count }
}
