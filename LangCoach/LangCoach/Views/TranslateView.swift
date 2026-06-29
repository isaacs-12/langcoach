import SwiftUI
import SwiftData

struct TranslateView: View {
    @Environment(Coach.self) private var coach
    @Query(sort: \StudyDocument.importedAt, order: .reverse) private var documents: [StudyDocument]

    @State private var direction: TranslationDirection = .enToKo
    @State private var difficulty: Difficulty = .easy
    @State private var useNotes = false
    @State private var sourceDoc: StudyDocument?

    @State private var prompt: String = ""
    @State private var answer: String = ""
    @State private var feedback: TranslationFeedback?
    @State private var phase: Phase = .setup
    @State private var errorText: String?
    @State private var score = ScoreTally()

    enum Phase { case setup, loadingPrompt, answering, grading, graded }
    enum Difficulty: String, CaseIterable, Identifiable {
        case easy, medium, hard
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !coach.hasKey { APIKeyMissingBanner() }
            content
        }
        .navigationTitle("Translate")
        .toolbar {
            ToolbarItem(placement: .principal) {
                if score.total > 0 {
                    Text("Avg \(score.average)% · \(score.total) done")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .setup:
            setupView
        case .loadingPrompt:
            loadingView("Writing a sentence for you…")
        case .answering, .grading, .graded:
            exerciseView
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 44)).foregroundStyle(Theme.brandGradient)
            Text("Translation practice").font(.title2.bold())
            Text("The coach gives you a sentence to translate, then grades your answer with specific feedback.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 14) {
                Picker("Direction", selection: $direction) {
                    ForEach(TranslationDirection.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Difficulty", selection: $difficulty) {
                    ForEach(Difficulty.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if !documents.isEmpty {
                    Toggle("Base sentences on one of my notes", isOn: $useNotes)
                    if useNotes {
                        Picker("Note", selection: $sourceDoc) {
                            Text("Any note").tag(Optional<StudyDocument>.none)
                            ForEach(documents) { Text($0.title).tag(Optional($0)) }
                        }
                    }
                }
            }
            .frame(maxWidth: 420)

            Button { nextPrompt() } label: {
                Text("Start").frame(maxWidth: 420)
            }
            .buttonStyle(.primary).frame(maxWidth: 420)
            .disabled(!coach.hasKey)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Exercise

    private var exerciseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(direction.label, systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Button("End session") { endSession() }
                        .buttonStyle(.link)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Translate this \(direction.sourceLabel.lowercased()):")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(prompt)
                        .font(.title3.weight(.medium))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .cardSurface()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your \(direction.targetLabel.lowercased()) translation:")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $answer)
                        .font(.body)
                        .frame(minHeight: 90)
                        .padding(8)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        .disabled(phase == .grading || phase == .graded)
                }

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(Theme.danger)
                }

                if phase == .graded, let feedback {
                    FeedbackCard(feedback: feedback)
                }

                actionRow
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            Spacer()
            switch phase {
            case .answering:
                Button("Check answer") { grade() }
                    .buttonStyle(.borderedProminent)
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            case .grading:
                ProgressView().controlSize(.small)
                Text("Grading…").foregroundStyle(.secondary)
            case .graded:
                Button("Next sentence") { nextPrompt() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Actions

    private func nextPrompt() {
        errorText = nil
        feedback = nil
        answer = ""
        phase = .loadingPrompt
        let context = useNotes ? (sourceDoc?.text ?? documents.first?.text) : nil
        Task {
            do {
                let sentence = try await coach.generateTranslationPrompt(
                    direction: direction,
                    difficulty: difficulty.rawValue,
                    context: context
                )
                await MainActor.run { prompt = sentence; phase = .answering }
            } catch {
                await MainActor.run { errorText = error.localizedDescription; phase = .setup }
            }
        }
    }

    private func grade() {
        let attempt = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attempt.isEmpty else { return }
        errorText = nil
        phase = .grading
        Task {
            do {
                let result = try await coach.gradeTranslation(
                    prompt: prompt, answer: attempt, direction: direction
                )
                await MainActor.run {
                    feedback = result
                    score.add(result.score)
                    phase = .graded
                }
            } catch {
                await MainActor.run { errorText = error.localizedDescription; phase = .answering }
            }
        }
    }

    private func endSession() {
        phase = .setup
        prompt = ""; answer = ""; feedback = nil; errorText = nil
    }
}

struct ScoreTally {
    private(set) var total = 0
    private(set) var sum = 0
    var average: Int { total == 0 ? 0 : Int(round(Double(sum) / Double(total))) }
    mutating func add(_ score: Int) { total += 1; sum += score }
}

private struct FeedbackCard: View {
    let feedback: TranslationFeedback

    private var tint: Color {
        switch feedback.verdict.lowercased() {
        case "correct": return Theme.success
        case "close": return Theme.warning
        default: return Theme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconName).foregroundStyle(tint)
                Text(feedback.verdict.capitalized).font(.headline).foregroundStyle(tint)
                Spacer()
                Text("\(feedback.score)%")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(tint)
            }
            if !feedback.corrected.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Natural translation").font(.caption).foregroundStyle(.secondary)
                    Text(feedback.corrected).font(.body.weight(.medium)).textSelection(.enabled)
                }
            }
            if !feedback.feedback.isEmpty {
                Text(feedback.feedback).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }

    private var iconName: String {
        switch feedback.verdict.lowercased() {
        case "correct": return "checkmark.seal.fill"
        case "close": return "checkmark.circle"
        default: return "xmark.circle"
        }
    }
}
