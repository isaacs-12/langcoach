import SwiftUI
import SwiftData

struct ConversationView: View {
    /// When set, this is a TARGETED lesson-review session locked to one note: the
    /// note picker/toggle is replaced by a fixed banner and the coach is steered to
    /// drill the lesson's grammar structures. Nil = the normal free-form practice.
    var lesson: StudyDocument? = nil

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
    @State private var showTranslations = false

    enum Level: String, CaseIterable, Identifiable {
        case beginner, intermediate, advanced
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var guidance: String {
            switch self {
            case .beginner: return "Use very simple words and short sentences. Mostly present tense."
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
            composer
        }
        .background(PracticeBackground())
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
        ScrollView {
            VStack(spacing: 26) {
                if let lesson {
                    SetupHero(
                        systemImage: "bubble.left.and.bubble.right.fill",
                        title: "Review by texting",
                        subtitle: "Chat in Korean with your coach, who keeps steering the conversation so you reuse the grammar and vocabulary from “\(lesson.title).”"
                    )
                } else {
                    SetupHero(
                        systemImage: "bubble.left.and.bubble.right.fill",
                        title: "Korean texting practice",
                        subtitle: "Text back and forth with your AI coach in Korean. It replies like a friend over messages and gently corrects your mistakes as you go."
                    )
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Level")
                        PillPicker(items: Level.allCases, selection: $level) { $0.label }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Topic")
                        TextField("Optional — e.g. ordering coffee", text: $topic)
                            .textFieldStyle(.plain)
                            .padding(.vertical, 10).padding(.horizontal, 13)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                    }

                    if lesson != nil {
                        // Locked to one lesson: no note picker, just the theme
                        // suggestions so the student can steer within the lesson.
                        if !activeThemes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) { themeChips }
                        }
                    } else if !documents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $useNotes) {
                                Label("Use vocab from my notes", systemImage: "book.closed")
                                    .font(.subheadline.weight(.medium))
                            }
                            .toggleStyle(.switch)
                            .tint(Theme.accent)

                            if useNotes {
                                Picker("Note", selection: $sourceDoc) {
                                    Text("Most recent note").tag(Optional<StudyDocument>.none)
                                    ForEach(documents) { Text($0.title).tag(Optional($0)) }
                                }
                                .labelsHidden()
                                if !activeThemes.isEmpty {
                                    themeChips
                                }
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: useNotes)
                    }
                }
                .cardSurface()
                .frame(maxWidth: 440)

                Button {
                    startConversation()
                } label: {
                    Label("Start chatting", systemImage: "sparkles")
                }
                .buttonStyle(.primary)
                .frame(maxWidth: 440)
                .disabled(!coach.hasKey || sending)
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
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
                    .padding(.vertical, 10).padding(.horizontal, 15)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.35)))
                        .shadow(color: canSend ? Theme.accent.opacity(0.3) : .clear, radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.easeOut(duration: 0.15), value: canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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

        Write "reply" in pure Korean only. Never add romanization, pronunciation, \
        or transliteration (e.g. "(jal ji-nae-se-yo?)") — the English goes in \
        "translation", not in the reply.

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
            if lesson != nil {
                // Targeted review: drill the lesson's grammar hard. Topics can roam,
                // but the grammar structures should recur across most replies.
                p += """


                The student just studied the lesson below and is REVIEWING it to \
                cement it. In the MAJORITY of your messages, use the lesson's grammar \
                structures (see KEY STRUCTURE and GRAMMAR) and steer the chat so the \
                student naturally has to use them back — ask questions that invite \
                those patterns. Favor the lesson's vocabulary. You may range beyond \
                the exact lesson topics, but keep the grammar focus throughout. Do \
                not mention that you were given notes.

                LESSON:
                \(context)
                """
            } else {
                p += """


                The student is studying the lesson below. Naturally weave this vocabulary \
                and these grammar points into the conversation so they get to practice them, \
                without forcing it. Do not mention that you were given notes.

                LESSON NOTES:
                \(context)
                """
            }
        }
        return p
    }

    /// Themes of the note currently feeding the chat — the tappable topic
    /// suggestions. Empty until the note has a distilled memory with a THEMES line.
    private var activeThemes: [String] {
        if let lesson { return lesson.themes }
        guard useNotes, let doc = sourceDoc ?? documents.first else { return [] }
        return doc.themes
    }

    /// Tappable chips of the lesson's themes, plus a "surprise me" that rotates
    /// through them — so the same lesson topics can be practiced over and over.
    private var themeChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Practice a theme from this lesson")
                .font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(activeThemes, id: \.self) { theme in
                    Button { toggleTheme(theme) } label: { Text(theme) }
                        .buttonStyle(ChipStyle(selected: topic == theme))
                }
                Button { rotateTheme() } label: {
                    Label("Surprise me", systemImage: "dice")
                }
                .buttonStyle(ChipStyle(selected: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Set this theme as the topic, or clear it if it's already selected.
    private func toggleTheme(_ theme: String) {
        topic = (topic == theme) ? "" : theme
    }

    /// Pick a lesson theme at random, preferring one different from the current
    /// topic so repeated taps keep cycling through the lesson.
    private func rotateTheme() {
        let pool = activeThemes.filter { $0 != topic }
        topic = (pool.isEmpty ? activeThemes : pool).randomElement() ?? topic
    }

    /// The distilled study memory to steer the chat: the locked review lesson when
    /// present, otherwise whichever note the user opted into (if any).
    private func notesContext() -> String? {
        let doc: StudyDocument?
        if let lesson { doc = lesson }
        else if useNotes { doc = sourceDoc ?? documents.first }
        else { doc = nil }
        guard let doc else { return nil }
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

// MARK: - Theme chips

/// A pill-shaped chip button. Filled with the accent when selected.
private struct ChipStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(
                selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.07)),
                in: Capsule()
            )
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

