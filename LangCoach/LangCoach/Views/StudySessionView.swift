import SwiftUI
import SwiftData

// MARK: - Session configuration

/// Which subset of cards to study.
enum StudyFilter: String, CaseIterable, Identifiable {
    case all
    case starred
    case due

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All cards"
        case .starred: return "Starred"
        case .due: return "Due now"
        }
    }
    var systemImage: String {
        switch self {
        case .all: return "rectangle.stack"
        case .starred: return "star.fill"
        case .due: return "clock"
        }
    }
}

/// The order cards are presented in during a session.
enum StudyOrder: String, CaseIterable, Identifiable {
    case inOrder
    case shuffle

    var id: String { rawValue }
    var label: String { self == .inOrder ? "In order" : "Shuffle" }
    var systemImage: String { self == .inOrder ? "list.number" : "shuffle" }
}

/// Builds the ordered queue for a session from a pool of cards.
func resolveStudyCards(_ pool: [Flashcard], filter: StudyFilter, order: StudyOrder) -> [Flashcard] {
    var result: [Flashcard]
    switch filter {
    case .all:
        result = pool
    case .starred:
        result = pool.filter(\.isStarred)
    case .due:
        result = pool.filter(\.isDue)
    }
    switch order {
    case .inOrder:
        // Natural reading order for browsing; due date when cramming what's due.
        if filter == .due {
            result.sort { $0.dueDate < $1.dueDate }
        } else {
            result.sort { $0.createdAt < $1.createdAt }
        }
    case .shuffle:
        result.shuffle()
    }
    return result
}

/// A resolved request to study a specific set of cards. Identifiable so it can drive a `.sheet`.
struct StudyRequest: Identifiable {
    let id = UUID()
    let title: String
    let cards: [Flashcard]
}

// MARK: - Setup popover

/// Lets the user pick a filter and order for a pool of cards, then start a session.
struct StudySetupView: View {
    let title: String
    let pool: [Flashcard]
    var onStart: (StudyRequest) -> Void

    @State private var filter: StudyFilter = .all
    @State private var order: StudyOrder = .inOrder

    private var resolved: [Flashcard] { resolveStudyCards(pool, filter: filter, order: order) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Study \(title)").font(.system(.headline, design: .rounded))

            Picker("Cards", selection: $filter) {
                ForEach(StudyFilter.allCases) { f in
                    Label(f.label, systemImage: f.systemImage).tag(f)
                }
            }
            .pickerStyle(.radioGroup)

            Picker("Order", selection: $order) {
                ForEach(StudyOrder.allCases) { o in
                    Label(o.label, systemImage: o.systemImage).tag(o)
                }
            }
            .pickerStyle(.radioGroup)

            HStack {
                Text("\(resolved.count) card\(resolved.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    onStart(StudyRequest(title: title, cards: resolved))
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(resolved.isEmpty)
            }
        }
        .padding()
        .frame(width: 260)
    }
}

// MARK: - Session

/// A focused spaced-repetition review session over a pre-resolved set of cards.
struct StudySessionView: View {
    let title: String
    let cards: [Flashcard]
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
                Text(title).font(.headline)
                Text("\(reviewedCount) reviewed · \(max(0, queue.count - index)) left")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let card = currentCard {
                Button {
                    card.isStarred.toggle()
                    try? context.save()
                } label: {
                    Image(systemName: card.isStarred ? "star.fill" : "star")
                        .foregroundStyle(card.isStarred ? Theme.warning : .secondary)
                }
                .buttonStyle(.plain)
                .help(card.isStarred ? "Unstar this card" : "Star this card")
            }
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
                .font(.system(size: 38, weight: .semibold, design: .rounded))
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
            Text("Session complete!").font(.system(.title2, design: .rounded).weight(.bold))
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
        queue = cards
        startCount = cards.count
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
