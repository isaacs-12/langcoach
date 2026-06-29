import Foundation

/// How well the user recalled a card during review.
enum ReviewGrade: Int, CaseIterable, Identifiable {
    case again = 0   // forgot
    case hard = 1
    case good = 2
    case easy = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var symbol: String {
        switch self {
        case .again: return "arrow.counterclockwise"
        case .hard: return "tortoise"
        case .good: return "checkmark"
        case .easy: return "hare"
        }
    }
}

/// SM-2 based spaced-repetition scheduler.
///
/// Adapted from the classic SuperMemo-2 algorithm with a four-button grading
/// scheme similar to Anki. Updates a card's interval, ease, and due date in place.
enum SRS {
    static func apply(_ grade: ReviewGrade, to card: Flashcard, now: Date = .now) {
        let minEase = 1.3

        if grade == .again {
            // Lapse: reset reps, shrink ease, show again soon.
            card.reps = 0
            card.lapses += 1
            card.ease = max(minEase, card.ease - 0.20)
            card.intervalDays = 0
            card.dueDate = now.addingTimeInterval(60 * 10) // 10 minutes
        } else {
            // Adjust ease based on how easy it felt.
            switch grade {
            case .hard: card.ease = max(minEase, card.ease - 0.15)
            case .good: break
            case .easy: card.ease += 0.15
            case .again: break
            }

            let nextInterval: Double
            switch card.reps {
            case 0:
                nextInterval = grade == .easy ? 4 : 1
            case 1:
                nextInterval = grade == .easy ? 6 : 3
            default:
                let multiplier = grade == .hard ? 1.2 : card.ease
                nextInterval = card.intervalDays * multiplier * (grade == .easy ? 1.3 : 1.0)
            }

            card.reps += 1
            card.intervalDays = max(1, nextInterval)
            card.dueDate = now.addingTimeInterval(card.intervalDays * 86_400)
        }

        card.lastReviewed = now
    }

    /// Human-readable preview of when a card will next appear for a given grade,
    /// without mutating the card. Useful for button captions.
    static func previewInterval(_ grade: ReviewGrade, for card: Flashcard) -> String {
        let copy = Flashcard(korean: card.korean, english: card.english)
        copy.reps = card.reps
        copy.ease = card.ease
        copy.intervalDays = card.intervalDays
        copy.lapses = card.lapses
        apply(grade, to: copy)

        let seconds = copy.dueDate.timeIntervalSinceNow
        if seconds < 3600 {
            return "\(max(1, Int(seconds / 60)))m"
        } else if seconds < 86_400 {
            return "\(Int(seconds / 3600))h"
        } else {
            return "\(Int(round(seconds / 86_400)))d"
        }
    }
}
