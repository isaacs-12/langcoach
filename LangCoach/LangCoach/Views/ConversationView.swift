import SwiftUI
import SwiftData

struct ConversationView: View {
    @Environment(Coach.self) private var coach
    @Query(sort: \StudyDocument.importedAt, order: .reverse) private var documents: [StudyDocument]

    @State private var level: Level = .beginner
    @State private var topic: String = ""
    @State private var useNotes = false
    @State private var sourceDoc: StudyDocument?
    @State private var messages: [ChatTurn] = []
    /// Clean history sent to the model (Korean text only).
    @State private var apiHistory: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var sending = false
    @State private var errorText: String?
    @State private var showTranslations = true

    enum Level: String, CaseIterable, Identifiable {
        case beginner, intermediate, advanced
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var guidance: String {
            switch self {
            case .beginner: return "Use very simple words and short sentences. Mostly present tense. Add furigana-style romanization sparingly."
            case .intermediate: return "Use everyday vocabulary and a natural mix of tenses and connectors."
            case .advanced: return "Text naturally as you would with a native, using idioms and varied grammar."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !coach.hasKey {
                APIKeyMissingBanner()
            }
            if messages.isEmpty {
                setupCard
            } else {
                transcript
            }
            Divider()
            composer
        }
        .navigationTitle("Conversation")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showTranslations) {
                    Label("Translations", systemImage: "character.bubble")
                }
                .toggleStyle(.button)
                .help("Show English translations of the coach's replies")
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    resetConversation()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .disabled(messages.isEmpty)
            }
        }
    }

    // MARK: - Setup

    private var setupCard: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brandGradient)
            Text("Korean texting practice").font(.title2.bold())
            Text("Text back and forth with your AI coach in Korean. It replies like a friend over messages and gently corrects your mistakes as you go.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Level", selection: $level) {
                    ForEach(Level.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Topic or scenario (optional) — e.g. ordering coffee", text: $topic)
                    .textFieldStyle(.roundedBorder)

                if !documents.isEmpty {
                    Toggle("Use vocab from my notes", isOn: $useNotes)
                    if useNotes {
                        Picker("Note", selection: $sourceDoc) {
                            Text("Most recent note").tag(Optional<StudyDocument>.none)
                            ForEach(documents) { Text($0.title).tag(Optional($0)) }
                        }
                    }
                }
            }
            .frame(maxWidth: 420)

            Button {
                startConversation()
            } label: {
                Text("Start chatting").frame(maxWidth: 420)
            }
            .buttonStyle(.primary)
            .frame(maxWidth: 420)
            .disabled(!coach.hasKey || sending)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { turn in
                        ChatBubble(turn: turn, showTranslation: showTranslations)
                            .id(turn.id)
                    }
                    if sending {
                        TypingIndicator().id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: sending) { _, isSending in
                if isSending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("한국어로 입력하세요…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
        .disabled(messages.isEmpty && !sending)
        .opacity(messages.isEmpty ? 0.5 : 1)
    }

    private var canSend: Bool {
        coach.hasKey && !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - System prompt

    private func systemPrompt() -> String {
        var p = """
        You are 코치, a warm, patient Korean texting partner for a language learner. \
        You are chatting over text messages, so write like a friend texting: short, \
        casual, natural. Level: \(level.rawValue). \(level.guidance)
        Keep each text reply concise (1-3 short sentences) and always keep the \
        conversation going by asking a question or inviting a response.

        Whenever the student writes something, check their Korean for mistakes \
        (grammar, particles, word choice, naturalness).

        Respond ONLY with JSON (no markdown fences) with these keys:
        "reply": your natural Korean text reply to continue the conversation,
        "translation": an English translation of your reply,
        "hasErrors": true/false — whether the student's last message had mistakes,
        "correction": if hasErrors, the corrected/natural Korean version of what they wrote, else "",
        "note": if hasErrors, a brief English explanation of the fix (1-2 sentences), else "".
        """
        if !topic.trimmingCharacters(in: .whitespaces).isEmpty {
            p += "\n\nToday's topic/scenario: \(topic)."
        }
        if let context = notesContext() {
            p += """


            The student is studying the lesson below. Naturally weave this vocabulary \
            and these grammar points into the conversation so they get to practice them, \
            without forcing it. Do not mention that you were given notes.

            LESSON NOTES:
            \(context)
            """
        }
        return p
    }

    /// The distilled study memory to steer the chat, if the user opted in.
    private func notesContext() -> String? {
        guard useNotes, let doc = sourceDoc ?? documents.first else { return nil }
        let memory = doc.studyMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !memory.isEmpty { return memory }
        // Fall back to a trimmed slice of raw text if no memory has been distilled yet.
        let raw = doc.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : String(raw.prefix(2000))
    }

    // MARK: - Actions

    private func startConversation() {
        errorText = nil
        sending = true
        // Kick off with an opening line from the coach.
        let opener = ChatMessage(role: .user, content: "(Start the conversation in Korean. Greet me and ask an opening question.)")
        Task {
            do {
                let raw = try await coach.reply(system: systemPrompt(), messages: [opener])
                let parsed = ConversationReply.parse(raw)
                await MainActor.run {
                    messages.append(ChatTurn(role: .coach, text: parsed.reply, translation: parsed.translation))
                    apiHistory = [ChatMessage(role: .assistant, content: parsed.reply)]
                    sending = false
                }
            } catch {
                await MainActor.run { errorText = error.localizedDescription; sending = false }
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, coach.hasKey else { return }
        errorText = nil
        draft = ""
        let userTurn = ChatTurn(role: .me, text: text)
        messages.append(userTurn)
        apiHistory.append(ChatMessage(role: .user, content: text))
        sending = true

        let history = apiHistory
        Task {
            do {
                let raw = try await coach.reply(system: systemPrompt(), messages: history)
                let parsed = ConversationReply.parse(raw)
                await MainActor.run {
                    // Attach correction to the user's message.
                    if parsed.hasErrors, let idx = messages.lastIndex(where: { $0.role == .me }) {
                        messages[idx].correction = CorrectionInfo(corrected: parsed.correction, note: parsed.note)
                    }
                    messages.append(ChatTurn(role: .coach, text: parsed.reply, translation: parsed.translation))
                    apiHistory.append(ChatMessage(role: .assistant, content: parsed.reply))
                    sending = false
                }
            } catch {
                await MainActor.run { errorText = error.localizedDescription; sending = false }
            }
        }
    }

    private func resetConversation() {
        messages = []
        apiHistory = []
        errorText = nil
        draft = ""
    }
}

// MARK: - Models

struct ChatTurn: Identifiable {
    enum Speaker { case me, coach }
    let id = UUID()
    var role: Speaker
    var text: String
    var translation: String? = nil
    var correction: CorrectionInfo? = nil
}

struct CorrectionInfo {
    var corrected: String
    var note: String
}

struct ConversationReply {
    var reply: String
    var translation: String
    var hasErrors: Bool
    var correction: String
    var note: String

    static func parse(_ raw: String) -> ConversationReply {
        let cleaned = Coach.stripFences(raw)
        if let data = cleaned.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ConversationReply(
                reply: (obj["reply"] as? String) ?? cleaned,
                translation: (obj["translation"] as? String) ?? "",
                hasErrors: (obj["hasErrors"] as? Bool) ?? false,
                correction: (obj["correction"] as? String) ?? "",
                note: (obj["note"] as? String) ?? ""
            )
        }
        // Fallback: treat the whole thing as the reply.
        return ConversationReply(reply: raw, translation: "", hasErrors: false, correction: "", note: "")
    }
}
