import Foundation
import SwiftData

/// A single vocab/phrase flashcard with SM-2 spaced-repetition scheduling state.
@Model
final class Flashcard {
    var korean: String
    var english: String
    /// Optional romanization / pronunciation hint.
    var reading: String
    /// Optional example sentence (Korean) or usage note.
    var example: String
    var notes: String
    var createdAt: Date
    /// Whether the user has starred this card for focused study.
    var isStarred: Bool = false

    // MARK: SM-2 scheduling state
    var dueDate: Date
    /// Inter-repetition interval in days.
    var intervalDays: Double
    /// Ease factor (SM-2), starts at 2.5.
    var ease: Double
    /// Number of successful repetitions in a row.
    var reps: Int
    /// Number of times the card has lapsed (been forgotten).
    var lapses: Int
    var lastReviewed: Date?

    var deck: Deck?

    init(
        korean: String,
        english: String,
        reading: String = "",
        example: String = "",
        notes: String = "",
        deck: Deck? = nil,
        createdAt: Date = .now
    ) {
        self.korean = korean
        self.english = english
        self.reading = reading
        self.example = example
        self.notes = notes
        self.deck = deck
        self.createdAt = createdAt
        self.dueDate = createdAt
        self.intervalDays = 0
        self.ease = 2.5
        self.reps = 0
        self.lapses = 0
        self.lastReviewed = nil
    }

    var isNew: Bool { reps == 0 }
    var isDue: Bool { dueDate <= .now }
}
