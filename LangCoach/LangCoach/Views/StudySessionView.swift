import SwiftUI
import SwiftData

/// A focused spaced-repetition review session for one deck.
struct StudySessionView: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var queue: [Flashcard] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var reviewedCount = 0
    @State private var startCount = 0
    @State private var flipFront = true   // true = show Korean first

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let card = currentCard {
                cardArea(card)
            } else {
                finishedView
            }
        }
        .frame(width: 620, height: 520)
        .onAppear(perform: startSession)
    }

    private var currentCard: Flashcard? {
        guard index < queue.count else { return nil }
        return queue[index]
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(deck.name).font(.headline)
                Text("\(reviewedCount) reviewed · \(max(0, queue.count - index)) left")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: $flipFront) {
                Text(flipFront ? "KO → EN" : "EN → KO").font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
        }
        .padding()
    }

    private func cardArea(_ card: Flashcard) -> some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(reviewedCount), total: Double(max(1, startCount)))
                .tint(Theme.accent)
                .padding(.horizontal).padding(.top, 8)

            Spacer()
            cardFace(card)
            Spacer()

            if revealed {
                gradeButtons(card)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Button("Show answer") {
                    withAnimation(.easeOut(duration: 0.15)) { revealed = true }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.space, modifiers: [])
                .padding()
            }
        }
    }

    private func cardFace(_ card: Flashcard) -> some View {
        let front = flipFront ? card.korean : card.english
        let back = flipFront ? card.english : card.korean
        return VStack(spacing: 18) {
            Text(front)
                .font(.system(size: 38, weight: .semibold))
                .multilineTextAlignment(.center)

            if flipFront && !card.reading.isEmpty && revealed {
                Text(card.reading).font(.title3).foregroundStyle(.secondary)
            }

            if revealed {
                Divider().frame(width: 120)
                Text(back)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                if !card.example.isEmpty {
                    Text(card.example)
                        .font(.callout).italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                if !card.notes.isEmpty {
                    Text(card.notes).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .cardSurface(padding: 30)
        .padding(.horizontal, 30)
    }

    private func gradeButtons(_ card: Flashcard) -> some View {
        HStack(spacing: 10) {
            ForEach(ReviewGrade.allCases) { grade in
                Button {
                    record(grade, card)
                } label: {
                    VStack(spacing: 3) {
                        Text(grade.label).font(.subheadline.weight(.semibold))
                        Text(SRS.previewInterval(grade, for: card))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: grade))
                .keyboardShortcut(KeyEquivalent(Character("\(grade.rawValue + 1)")), modifiers: [])
            }
        }
        .padding()
    }

    private func tint(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return Theme.danger
        case .hard: return Theme.warning
        case .good: return Theme.accent
        case .easy: return Theme.success
        }
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.success)
            Text("Session complete!").font(.title2.bold())
            Text("You reviewed \(reviewedCount) card\(reviewedCount == 1 ? "" : "s").")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private func startSession() {
        var due = deck.dueCards()
        // If nothing is strictly due, fall back to new cards then a small refresher.
        if due.isEmpty {
            due = deck.cards.filter(\.isNew)
        }
        if due.isEmpty {
            due = Array(deck.cards.sorted { $0.dueDate < $1.dueDate }.prefix(20))
        }
        queue = due
        startCount = due.count
        index = 0
        revealed = false
        reviewedCount = 0
    }

    private func record(_ grade: ReviewGrade, _ card: Flashcard) {
        SRS.apply(grade, to: card)
        try? context.save()
        reviewedCount += 1

        // Re-show lapsed cards later in the same session.
        if grade == .again {
            queue.append(card)
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            index += 1
            revealed = false
        }
    }
}
