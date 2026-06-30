import Foundation
import Observation

/// Central service that holds LLM settings, resolves the active provider/client,
/// and exposes the high-level coaching operations used across the app.
@Observable
final class Coach {
    var providerKind: LLMProviderKind {
        didSet { UserDefaults.standard.set(providerKind.rawValue, forKey: Keys.provider) }
    }
    /// High-quality model used for conversation.
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }
    /// Cheap/fast model used for grading, sentence generation, vocab extraction,
    /// and note distillation.
    var quickModel: String {
        didSet { UserDefaults.standard.set(quickModel, forKey: Keys.quickModel) }
    }
    /// Bumped whenever the key changes so SwiftUI views recompute `hasKey`.
    private(set) var keyRevision: Int = 0

    private enum Keys {
        static let provider = "settings.provider"
        static let model = "settings.model"
        static let quickModel = "settings.quickModel"
    }

    init() {
        let defaults = UserDefaults.standard
        let kind = LLMProviderKind(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .gemini
        self.providerKind = kind
        self.model = defaults.string(forKey: Keys.model) ?? kind.defaultModel
        self.quickModel = defaults.string(forKey: Keys.quickModel) ?? kind.defaultQuickModel
    }

    // MARK: - API key management

    var hasKey: Bool {
        _ = keyRevision // establish dependency for @Observable
        guard let k = Keychain.get(account: providerKind.keychainAccount) else { return false }
        return !k.isEmpty
    }

    func key(for kind: LLMProviderKind) -> String {
        Keychain.get(account: kind.keychainAccount) ?? ""
    }

    func setKey(_ value: String, for kind: LLMProviderKind) {
        Keychain.set(value.trimmingCharacters(in: .whitespacesAndNewlines), account: kind.keychainAccount)
        keyRevision += 1
    }

    func switchProvider(to kind: LLMProviderKind) {
        providerKind = kind
        model = kind.defaultModel
        quickModel = kind.defaultQuickModel
        keyRevision += 1
    }

    // MARK: - Client resolution

    private func makeClient(model: String) throws -> LLMClient {
        let key = Keychain.get(account: providerKind.keychainAccount) ?? ""
        guard !key.isEmpty else { throw LLMError.missingKey(providerKind) }
        switch providerKind {
        case .gemini: return GeminiClient(apiKey: key, model: model)
        case .claude: return ClaudeClient(apiKey: key, model: model)
        case .openai: return OpenAIClient(apiKey: key, model: model)
        }
    }

    /// Low-level chat entry point. Uses the high-quality conversation model.
    func reply(system: String, messages: [ChatMessage]) async throws -> String {
        let client = try makeClient(model: model)
        return try await client.send(system: system, messages: messages)
    }

    /// Single-shot prompt on the high-quality model.
    func complete(system: String, user: String) async throws -> String {
        try await reply(system: system, messages: [ChatMessage(role: .user, content: user)])
    }

    /// Single-shot prompt on the cheap/fast model, for grading and other
    /// utility tasks where cost matters more than nuance.
    func quickComplete(system: String, user: String, temperature: Double? = nil) async throws -> String {
        let client = try makeClient(model: quickModel)
        return try await client.send(
            system: system,
            messages: [ChatMessage(role: .user, content: user)],
            temperature: temperature
        )
    }

    // MARK: - High-level coaching operations

    /// Extracts vocabulary pairs from a chunk of class notes. Returns JSON-decoded items.
    func extractVocab(from notes: String) async throws -> [ExtractedVocab] {
        let system = """
        You are a Korean language teaching assistant. Extract the most useful \
        vocabulary words and short phrases for a student to study from the provided \
        class notes. Prefer dictionary forms. Skip English-only lines, headers, and dates.

        Respond ONLY with a JSON array (no markdown fences) of objects with keys:
        "korean" (the Korean word/phrase),
        "english" (concise English meaning),
        "reading" (romanization, may be empty),
        "example" (a short Korean example sentence if present in the notes, else empty).
        Return at most 40 items. If there is no Korean vocabulary, return [].
        """
        let raw = try await quickComplete(system: system, user: String(notes.prefix(12_000)))
        return try Self.decodeVocab(raw)
    }

    /// Distills raw lesson notes into a compact "study memory" — the key vocab,
    /// grammar points, and themes needed to drive practice — so the full note
    /// text never has to be sent to the model again. Uses the cheap/fast model.
    func distillNotes(_ notes: String) async throws -> String {
        let system = """
        You are a Korean teaching assistant. Read the class notes and produce a \
        compact STUDY MEMORY that captures everything needed to practice this \
        lesson, with no fluff. Use exactly this plain-text format:

        VOCAB:
        - 한국어 — English meaning (reading if helpful)
        (the most important items, up to ~30)

        GRAMMAR:
        - pattern — one-line explanation
        (key grammar/particles introduced in the lesson)

        THEMES: a short comma-separated list of topics or scenarios

        Keep Korean in Korean. Stay under ~250 words. Output ONLY this text — \
        no markdown fences, no preamble, no closing remarks. If the notes contain \
        no Korean content, output exactly: (no Korean content)
        """
        return try await quickComplete(system: system, user: String(notes.prefix(12_000)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Grades a translation attempt. `direction` describes which way to translate.
    func gradeTranslation(
        prompt: String,
        answer: String,
        direction: TranslationDirection
    ) async throws -> TranslationFeedback {
        let system = """
        You are a precise but encouraging Korean tutor grading a translation exercise. \
        The student is translating \(direction.instruction).

        Respond ONLY with JSON (no markdown fences) with keys:
        "score" (integer 0-100),
        "verdict" (one of "correct", "close", "incorrect"),
        "corrected" (the most natural correct translation),
        "feedback" (2-4 sentences: what was right, what to fix, and why; mention grammar/particles naturally).
        Be fair: accept natural variations and synonyms.
        """
        let user = """
        SOURCE (\(direction.sourceLabel)): \(prompt)
        STUDENT ANSWER (\(direction.targetLabel)): \(answer)
        """
        let raw = try await quickComplete(system: system, user: user)
        return try Self.decodeFeedback(raw)
    }

    /// Topics rotated through to keep generated sentences varied.
    private static let translationTopics = [
        "food and cooking", "weather and seasons", "family and friends",
        "school or work", "hobbies and free time", "shopping and money",
        "travel and directions", "daily routines", "health and the body",
        "technology and phones", "feelings and opinions", "nature and animals",
        "time and schedules", "home and furniture", "clothing", "sports and exercise",
        "music and movies", "the city and transportation", "plans and appointments",
    ]

    /// Sentence shapes rotated through so prompts aren't all simple statements.
    private static let translationStructures = [
        "a simple statement", "a question", "a negative sentence",
        "a sentence in the past tense", "a sentence about a future plan",
        "a sentence with a time expression", "a sentence with a location",
        "a sentence expressing a want or preference",
        "a sentence giving a reason ('because…')",
        "a compound sentence joining two related ideas",
    ]

    /// Generates a sentence to translate, optionally themed around the user's notes.
    /// `avoid` lists recently shown sentences the model should not repeat.
    func generateTranslationPrompt(
        direction: TranslationDirection,
        difficulty: String,
        context: String?,
        avoid: [String] = []
    ) async throws -> String {
        var system = """
        You generate single sentences for a Korean translation exercise. \
        Difficulty: \(difficulty). Output ONLY the sentence to be translated, \
        with no quotes, labels, or extra text. Make every sentence fresh and \
        distinct: vary the subject, verb, vocabulary, tense, and phrasing, and \
        avoid clichéd textbook sentences.
        """
        if direction == .enToKo {
            system += " Output an English sentence for the student to translate into Korean."
        } else {
            system += " Output a Korean sentence for the student to translate into English."
        }

        let topic = Self.translationTopics.randomElement() ?? "everyday life"
        let structure = Self.translationStructures.randomElement() ?? "a simple statement"
        var user: String
        if let context, !context.isEmpty {
            user = "Base the vocabulary and themes on these class notes:\n\(String(context.prefix(4000)))"
        } else {
            user = "Use common everyday vocabulary appropriate to the difficulty."
        }
        user += "\n\nFor this one, write \(structure) about \(topic)."
        if !avoid.isEmpty {
            let list = avoid.suffix(8).map { "- \($0)" }.joined(separator: "\n")
            user += "\n\nDo NOT repeat or closely resemble any of these recent sentences:\n\(list)"
        }
        return try await quickComplete(system: system, user: user, temperature: 0.9)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON decoding helpers

    static func stripFences(_ s: String) -> String {
        var text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            // Remove leading ```json or ``` and trailing ```
            if let range = text.range(of: "\n") {
                text = String(text[range.upperBound...])
            }
            if let close = text.range(of: "```", options: .backwards) {
                text = String(text[..<close.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeVocab(_ raw: String) throws -> [ExtractedVocab] {
        let cleaned = stripFences(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.badResponse(raw)
        }
        do {
            return try JSONDecoder().decode([ExtractedVocab].self, from: data)
        } catch {
            throw LLMError.badResponse("Could not parse vocab JSON.\n\(String(raw.prefix(400)))")
        }
    }

    static func decodeFeedback(_ raw: String) throws -> TranslationFeedback {
        let cleaned = stripFences(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.badResponse(raw)
        }
        do {
            return try JSONDecoder().decode(TranslationFeedback.self, from: data)
        } catch {
            throw LLMError.badResponse("Could not parse feedback JSON.\n\(String(raw.prefix(400)))")
        }
    }
}

// MARK: - DTOs

struct ExtractedVocab: Codable, Identifiable, Hashable {
    var id = UUID()
    var korean: String
    var english: String
    var reading: String = ""
    var example: String = ""

    private enum CodingKeys: String, CodingKey { case korean, english, reading, example }
}

enum TranslationDirection: String, CaseIterable, Identifiable {
    case enToKo
    case koToEn

    var id: String { rawValue }
    var label: String { self == .enToKo ? "English → Korean" : "Korean → English" }
    var sourceLabel: String { self == .enToKo ? "English" : "Korean" }
    var targetLabel: String { self == .enToKo ? "Korean" : "English" }
    var instruction: String {
        self == .enToKo ? "from English into Korean" : "from Korean into English"
    }
}

struct TranslationFeedback: Codable {
    var score: Int
    var verdict: String
    var corrected: String
    var feedback: String
}
