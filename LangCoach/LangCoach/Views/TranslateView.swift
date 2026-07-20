import SwiftUI
import SwiftData

struct TranslateView: View {
    /// When set, this is a TARGETED lesson-review session locked to one note: every
    /// sentence is built from that lesson's vocabulary and grammar instead of random
    /// topics. Nil = the normal free-form practice.
    var lesson: StudyDocument? = nil

    @Environment(Coach.self) private var coach
    @Query(sort: \StudyDocument.importedAt, order: .reverse) private var documents: [StudyDocument]

    @State private var direction: TranslationDirection = .enToKo
    @State private var difficulty: Difficulty = .easy
    @State private var useNotes = false
    @State private var sourceDoc: StudyDocument?

    @State private var prompt: String = ""
    @State private var recentPrompts: [String] = []
    /// A shuffled queue of the lesson's vocab entries, drained a few per prompt so
    /// review sentences rotate through the whole list. Refilled when emptied.
    @State private var vocabQueue: [String] = []
    @State private var answer: String = ""
    @State private var feedback: TranslationFeedback?
    @State private var phase: Phase = .setup
    @State private var errorText: String?
    @State private var score = ScoreTally()
    /// The revealed "cheat" translation of the current prompt, if peeked.
    @State private var hint: String?
    @State private var loadingHint = false

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
        .background(PracticeBackground())
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
        ScrollView {
            VStack(spacing: 26) {
                if let lesson {
                    SetupHero(
                        systemImage: "character.book.closed.fill",
                        title: "Review by translating",
                        subtitle: "Every sentence is built from the vocabulary and grammar in “\(lesson.title)” so you drill exactly what the lesson covered."
                    )
                } else {
                    SetupHero(
                        systemImage: "character.book.closed.fill",
                        title: "Translation practice",
                        subtitle: "The coach gives you a sentence to translate, then grades your answer with specific feedback."
                    )
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Direction")
                        PillPicker(items: TranslationDirection.allCases, selection: $direction) { $0.label }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Difficulty")
                        PillPicker(items: Difficulty.allCases, selection: $difficulty) { $0.label }
                    }

                    if let lesson {
                        LessonLockBanner(
                            title: lesson.title,
                            detail: lesson.vocabEntries.isEmpty
                                ? "Sentences will draw on this lesson's content."
                                : "Sentences will rotate through this lesson's \(lesson.vocabEntries.count) vocabulary words."
                        )
                    } else if !documents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $useNotes) {
                                Label("Base sentences on my notes", systemImage: "book.closed")
                                    .font(.subheadline.weight(.medium))
                            }
                            .toggleStyle(.switch)
                            .tint(Theme.accent)

                            if useNotes {
                                Picker("Note", selection: $sourceDoc) {
                                    Text("Any note").tag(Optional<StudyDocument>.none)
                                    ForEach(documents) { Text($0.title).tag(Optional($0)) }
                                }
                                .labelsHidden()
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: useNotes)
                    }
                }
                .cardSurface()
                .frame(maxWidth: 440)

                Button { nextPrompt() } label: {
                    Label("Start", systemImage: "sparkles")
                }
                .buttonStyle(.primary).frame(maxWidth: 440)
                .disabled(!coach.hasKey)
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                    Spacer()
                    Button { endSession() } label: {
                        Label("End session", systemImage: "xmark")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Translate this \(direction.sourceLabel.lowercased())", systemImage: "quote.opening")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Group {
                        if direction == .koToEn {
                            // Korean source: double-click any word to look it up.
                            TappableKoreanText(text: prompt, source: .translation)
                        } else {
                            Text(prompt).textSelection(.enabled)
                        }
                    }
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .cardSurface(padding: 22)

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Your \(direction.targetLabel.lowercased()) translation")
                    TextEditor(text: $answer)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 96)
                        .padding(10)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                        .disabled(phase == .grading || phase == .graded)
                }

                if phase == .answering {
                    hintRow
                }

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(Theme.danger)
                }

                if phase == .graded, let feedback {
                    FeedbackCard(feedback: feedback, direction: direction)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                actionRow
            }
            .padding(24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: phase)
        }
    }

    /// The "peek at the answer" cheat: a subtle button that fetches and reveals a
    /// suggested translation of the prompt when the learner is stuck.
    @ViewBuilder
    private var hintRow: some View {
        if let hint {
            VStack(alignment: .leading, spacing: 4) {
                Label("Suggested translation", systemImage: "eye.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Group {
                    if direction == .enToKo {
                        // Korean target: double-click any word to look it up.
                        TappableKoreanText(text: hint, source: .translation)
                    } else {
                        Text(hint).textSelection(.enabled)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.25)))
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Button { peek() } label: {
                if loadingHint {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Revealing…")
                    }
                } else {
                    Label("Peek at the answer", systemImage: "eye")
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .disabled(loadingHint || !coach.hasKey)
            .help("Reveal a suggested translation to help you when you're stuck")
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            Spacer()
            switch phase {
            case .answering:
                Button { grade() } label: {
                    Label("Check answer", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            case .grading:
                ProgressView().controlSize(.small)
                Text("Grading…").foregroundStyle(.secondary)
            case .graded:
                Button { nextPrompt() } label: {
                    Label("Next sentence", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Actions

    private func peek() {
        guard hint == nil, !loadingHint, coach.hasKey else { return }
        errorText = nil
        loadingHint = true
        Task {
            do {
                let suggestion = try await coach.translationHint(for: prompt, direction: direction)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) { hint = suggestion }
                    loadingHint = false
                }
            } catch {
                await MainActor.run { errorText = error.localizedDescription; loadingHint = false }
            }
        }
    }

    private func nextPrompt() {
        errorText = nil
        feedback = nil
        answer = ""
        hint = nil
        loadingHint = false
        phase = .loadingPrompt
        // Prefer the compact distilled memory; fall back to raw text if not yet generated.
        let context: String?
        if useNotes, let doc = sourceDoc ?? documents.first {
            context = doc.hasMemory ? doc.studyMemory : doc.text
        } else {
            context = nil
        }
        // Draining the vocab queue mutates state, so do it here on the main actor
        // (before the background Task) rather than inside the request closure.
        let targetVocab = lesson != nil ? nextTargetVocab() : []
        Task {
            do {
                let sentence: String
                if let lesson {
                    sentence = try await coach.generateVocabReviewPrompt(
                        direction: direction,
                        difficulty: difficulty.rawValue,
                        memory: lesson.hasMemory ? lesson.studyMemory : lesson.text,
                        targetVocab: targetVocab,
                        avoid: recentPrompts
                    )
                } else {
                    sentence = try await coach.generateTranslationPrompt(
                        direction: direction,
                        difficulty: difficulty.rawValue,
                        context: context,
                        avoid: recentPrompts
                    )
                }
                await MainActor.run {
                    prompt = sentence
                    recentPrompts.append(sentence)
                    if recentPrompts.count > 8 {
                        recentPrompts.removeFirst(recentPrompts.count - 8)
                    }
                    phase = .answering
                }
            } catch {
                await MainActor.run { errorText = error.localizedDescription; phase = .setup }
            }
        }
    }

    /// Pulls the next few lesson vocab entries to build a sentence around, refilling
    /// and reshuffling the queue once exhausted so review keeps cycling the whole
    /// list without a visible tracker.
    private func nextTargetVocab(_ count: Int = 3) -> [String] {
        guard let lesson, !lesson.vocabEntries.isEmpty else { return [] }
        if vocabQueue.isEmpty { vocabQueue = lesson.vocabEntries.shuffled() }
        let n = min(count, vocabQueue.count)
        let picked = Array(vocabQueue.prefix(n))
        vocabQueue.removeFirst(n)
        return picked
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
        hint = nil; loadingHint = false
        recentPrompts.removeAll()
        vocabQueue.removeAll()
    }
}

/// A read-only banner shown in place of the note picker during a targeted lesson
/// review, making it clear which lesson the sentences are locked to.
private struct LessonLockBanner: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    var direction: TranslationDirection

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
                    if direction == .enToKo {
                        // Korean target: double-click any word to look it up.
                        TappableKoreanText(text: feedback.corrected, source: .translation)
                            .font(.body.weight(.medium))
                    } else {
                        Text(feedback.corrected).font(.body.weight(.medium)).textSelection(.enabled)
                    }
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
