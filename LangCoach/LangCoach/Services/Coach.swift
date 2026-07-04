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

    /// Retries a transient-failing LLM call (rate limits, 5xx, dropped
    /// connections) with exponential backoff. Providers like Gemini return 503
    /// "high demand" under load; without this, a single blip silently fails a
    /// distillation or grade. Non-transient errors (bad key, 4xx) propagate at once.
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var delay: UInt64 = 700_000_000 // 0.7s, doubled each attempt
        for attempt in 0..<4 {
            do {
                return try await operation()
            } catch {
                let transient = (error as? LLMError)?.isRetryable ?? (error is URLError)
                guard transient, attempt < 3 else { throw error }
                try? await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
        throw LLMError.badResponse("exhausted retries")
    }

    /// Low-level chat entry point. Uses the high-quality conversation model.
    func reply(system: String, messages: [ChatMessage]) async throws -> String {
        let client = try makeClient(model: model)
        return try await withRetry { try await client.send(system: system, messages: messages) }
    }

    /// Single-shot prompt on the high-quality model.
    func complete(system: String, user: String) async throws -> String {
        try await reply(system: system, messages: [ChatMessage(role: .user, content: user)])
    }

    /// Single-shot prompt on the cheap/fast model, for grading and other
    /// utility tasks where cost matters more than nuance.
    func quickComplete(system: String, user: String, temperature: Double? = nil) async throws -> String {
        let client = try makeClient(model: quickModel)
        return try await withRetry {
            try await client.send(
                system: system,
                messages: [ChatMessage(role: .user, content: user)],
                temperature: temperature
            )
        }
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

    /// The structured shape the distiller returns. Asking for JSON (rather than a
    /// free-form 4-section blob) is far more reliable on the fast model, which
    /// otherwise intermittently drops whole sections — sometimes vocab, sometimes
    /// themes. Keys are optional so a partial response still decodes.
    private struct DistilledMemory: Decodable {
        var keyStructure: String?
        var vocab: [String]?
        var grammar: [String]?
        var themes: [String]?
    }

    /// Distills raw lesson notes into a compact "study memory" — the key vocab,
    /// grammar points, and themes needed to drive practice — so the full note
    /// text never has to be sent to the model again. Uses the cheap/fast model.
    ///
    /// The model returns JSON, which we validate and then render into the stable
    /// plain-text format the rest of the app reads. We retry if vocab comes back
    /// empty rather than storing a memory with no words to practice.
    func distillNotes(_ notes: String) async throws -> String {
        let system = """
        You are a Korean teaching assistant. Read the class notes and distill them \
        into a STUDY MEMORY for practice.

        Text wrapped in **double asterisks** was BOLD in the notes (high priority — \
        capture it, especially the key grammar structure). But bold is a hint, NOT a \
        filter: also include the lesson's other important vocabulary and grammar \
        even when it wasn't bolded. Never include the ** markers in your output.

        Respond ONLY with a JSON object (no markdown fences) with EXACTLY these \
        keys, ALL required:
        "keyStructure": string — the single most important grammar structure this \
        lesson teaches, as "pattern — one-line explanation" with a short Korean \
        example if present. Empty string "" if the lesson has no clear structure.
        "vocab": array of strings, each "한국어 — English meaning" (add a reading if \
        helpful). Include EVERY useful word or phrase the lesson introduces — aim \
        for 15-30, more when the lesson is vocab-heavy. This MUST NOT be empty when \
        the notes contain Korean words.
        "grammar": array of strings, each "pattern — one-line explanation", for the \
        other key grammar/particles beyond keyStructure.
        "themes": array of 3-6 short conversation topics or scenarios (noun \
        phrases, e.g. "ordering at a café", "asking prices").

        Keep Korean in Korean. If the notes contain no Korean at all, return every \
        key empty.
        """
        let input = String(notes.prefix(12_000))
        var last: DistilledMemory?
        for _ in 0..<3 {
            let raw = try await quickComplete(system: system, user: input, temperature: 0.2)
            guard let parsed = Self.decodeMemory(raw) else { continue }
            last = parsed
            // Accept as soon as we have real vocab; otherwise retry (a fresh sample
            // usually recovers the dropped list).
            if !(parsed.vocab ?? []).isEmpty { return Self.renderMemory(parsed) }
        }
        // No vocab after retries: render what we have, or signal an empty note.
        if let last, Self.hasContent(last) { return Self.renderMemory(last) }
        return "(no Korean content)"
    }

    private static func decodeMemory(_ raw: String) -> DistilledMemory? {
        guard let data = stripFences(raw).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DistilledMemory.self, from: data)
    }

    private static func hasContent(_ m: DistilledMemory) -> Bool {
        !(m.vocab ?? []).isEmpty || !(m.grammar ?? []).isEmpty
            || !(m.themes ?? []).isEmpty || !(m.keyStructure ?? "").isEmpty
    }

    /// Renders parsed JSON back into the plain-text "study memory" the UI displays,
    /// the themes parser reads, and conversation/translation send as context.
    private static func renderMemory(_ m: DistilledMemory) -> String {
        func bullets(_ items: [String]?) -> String {
            (items ?? [])
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t-•")) }
                .filter { !$0.isEmpty }
                .map { "- \($0)" }
                .joined(separator: "\n")
        }
        let ks = (m.keyStructure ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let themes = (m.themes ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return """
        KEY STRUCTURE: \(ks.isEmpty ? "none" : ks)

        VOCAB:
        \(bullets(m.vocab))

        GRAMMAR:
        \(bullets(m.grammar))

        THEMES: \(themes)
        """
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

    /// Looks up a single Korean word as it appears in a sentence and returns its
    /// dictionary/root form plus a definition — context-aware, so a conjugated verb
    /// resolves to its 다-form and a noun+particle resolves to the bare noun. Uses
    /// the cheap/fast model.
    func defineWord(_ word: String, in sentence: String) async throws -> WordDefinition {
        let system = """
        You are a Korean dictionary for an English-speaking learner. The learner \
        tapped a single Korean word as it appears in a sentence. Explain that word's \
        ROOT / DICTIONARY form — never the surface (inflected) form.

        - Conjugated verb or adjective → the dictionary form ending in 다 \
        (e.g. 먹었어요 → 먹다, 예뻐요 → 예쁘다).
        - Noun with an attached particle → the bare noun, and name the particle in \
        the note (e.g. 밥을 → 밥, note: object particle 을).
        - Give the definition of that dictionary form's meaning in THIS context \
        (pick the right sense for the sentence).

        Respond ONLY with JSON (no markdown fences) with these keys, all required:
        "word": the tapped surface word, cleaned of punctuation,
        "dictionaryForm": the root / dictionary form,
        "reading": romanization of the dictionary form (may be empty),
        "partOfSpeech": short English part of speech (e.g. "verb", "noun", "particle", "adjective", "adverb"),
        "meaning": a concise English definition of the root meaning that fits this context,
        "note": one short English note on how it is used here — tense, politeness, \
        attached particle, or nuance. Empty "" if there is nothing useful to add.
        """
        let user = """
        SENTENCE: \(sentence)
        TAPPED WORD: \(word)
        """
        let raw = try await quickComplete(system: system, user: user, temperature: 0.2)
        let def = try Self.decodeDefinition(raw)
        // A well-formed but empty object (wrong shape that still decoded) is a miss.
        guard !def.dictionaryForm.isEmpty || !def.meaning.isEmpty else {
            throw LLMError.badResponse("Empty definition for \(word)")
        }
        return def
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

    static func decodeDefinition(_ raw: String) throws -> WordDefinition {
        let cleaned = stripFences(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.badResponse(raw)
        }
        do {
            return try JSONDecoder().decode(WordDefinition.self, from: data)
        } catch {
            throw LLMError.badResponse("Could not parse definition JSON.\n\(String(raw.prefix(400)))")
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

/// A context-aware dictionary lookup for one tapped Korean word. Decoded
/// tolerantly: any missing key falls back to "" so a partial response from the
/// fast model still yields something showable rather than throwing.
struct WordDefinition: Hashable {
    var word: String
    var dictionaryForm: String
    var reading: String
    var partOfSpeech: String
    var meaning: String
    var note: String
}

extension WordDefinition: Decodable {
    private enum CodingKeys: String, CodingKey {
        case word, dictionaryForm, reading, partOfSpeech, meaning, note
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        word = str(.word)
        dictionaryForm = str(.dictionaryForm)
        reading = str(.reading)
        partOfSpeech = str(.partOfSpeech)
        meaning = str(.meaning)
        note = str(.note)
    }
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
