# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lang Coach is a **local-first macOS (SwiftUI) Korean study app**. Class notes are imported and stored on-device; the only network calls are AI requests to a user-chosen LLM provider. The Xcode project lives in the nested `LangCoach/` directory (so the project file is `LangCoach/LangCoach.xcodeproj`).

## Build & run

```bash
# Build (Debug, unsigned — matches the allowed dev workflow)
cd LangCoach && xcodebuild -project LangCoach.xcodeproj -scheme LangCoach \
  -configuration Debug -destination 'platform=macOS' build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/LangCoach-*/Build/Products/Debug/LangCoach.app
```

There is **no test target** and no linter configured — verification is by building and running the app.

## Architecture

**`Coach` is the center of gravity.** It's an `@Observable` class created once at the App level ([LangCoachApp.swift](LangCoach/LangCoach/LangCoachApp.swift)) and injected via `.environment(coach)` into **both** the `WindowGroup` and the `Settings` scene. This dual injection is load-bearing: `Settings` is a separate scene tree, so omitting it from there makes `@Environment(Coach.self)` crash when Settings opens. Views read it with `@Environment(Coach.self)`; never create a second `Coach()` instance (it would desync key/model state across scenes).

**Two-tier model routing for cost control.** `Coach` holds two model settings:
- `model` (chat model) — used by `reply()`/`complete()` for **conversation only**.
- `quickModel` — used by `quickComplete()` for grading, sentence generation, vocab extraction, and note distillation.

When adding an LLM-backed feature, deliberately choose `complete` vs `quickComplete` based on whether output quality or cost dominates. Per-provider defaults (`defaultModel`, `defaultQuickModel`, `suggestedModels`) live in `LLMProviderKind` ([LLMProvider.swift](LangCoach/LangCoach/Services/LLM/LLMProvider.swift)).

**Provider abstraction.** All vendors implement the `LLMClient` protocol (`send(system:messages:)`). `Coach.makeClient(model:)` switches on `LLMProviderKind` to build `GeminiClient` / `ClaudeClient` / `OpenAIClient`. To add a provider: add a case to `LLMProviderKind` (with display name, default models, key URL, keychain account) and a client conforming to `LLMClient`. Shared HTTP status validation is `HTTPHelper.validate` (defined at the bottom of [OpenAIClient.swift](LangCoach/LangCoach/Services/LLM/OpenAIClient.swift)).

**Structured LLM output is text-parsed, not function-called.** High-level `Coach` methods ask the model for raw JSON (no markdown fences), then `Coach.stripFences` + `JSONDecoder`/`JSONSerialization` parse it (see `decodeVocab`, `decodeFeedback`, and `ConversationReply.parse` in [ConversationView.swift](LangCoach/LangCoach/Views/ConversationView.swift)). Parsers are written to degrade gracefully (e.g. fall back to treating the whole response as the reply). Match this pattern for new structured calls rather than introducing tool/function calling.

**Distilled "study memory".** Imported notes are summarized once into a compact `studyMemory` (key vocab + grammar + themes) via `Coach.distillNotes` on the quick model, stored on `StudyDocument`. This is the practice context source: both Translation and Conversation send `studyMemory` (falling back to a trimmed slice of raw `text` when it's empty) instead of full note text, to keep tokens low. Distillation kicks off automatically on import in [LibraryView.swift](LangCoach/LangCoach/Views/LibraryView.swift) when a key is set, and can be (re)generated manually there.

**Persistence split — three stores, deliberately separated:**
- **SwiftData** (`StudyDocument`, `Deck`, `Flashcard`) — the `ModelContainer` is built in `LangCoachApp.init`. Schema migrations are lightweight: new `@Model` properties must have defaults (as `studyMemory` does).
- **Keychain** ([Keychain.swift](LangCoach/LangCoach/Services/Keychain.swift)) — API keys only, one per provider (`keychainAccount`). Keys never touch UserDefaults or SwiftData.
- **UserDefaults** — non-secret settings (`providerKind`, `model`, `quickModel`).

**App is sandboxed.** Entitlements allow outbound network + user-selected read-only file access. File import (`DocumentImporter`, supports txt/md/pdf/rtf/docx/doc/html) must run inside a `startAccessingSecurityScopedResource()` block — see `handleImport` in LibraryView.

**Flashcards use SM-2 spaced repetition** ([SRS.swift](LangCoach/LangCoach/Services/SRS.swift)), an Anki-style four-button (`again/hard/good/easy`) scheduler that mutates a `Flashcard`'s interval/ease/due date in place.

## Conventions

- The four main sections are an `AppSection` enum driving a `NavigationSplitView` in [ContentView.swift](LangCoach/LangCoach/Views/ContentView.swift): Library, Flashcards, Conversation, Translate.
- Conversation practice is **text/messaging-based** ("texting"), not speech — there is no audio/TTS code, and prompts/labels intentionally frame it as texting.
- Shared colors/gradients/styles live in [Theme.swift](LangCoach/LangCoach/Views/Theme.swift); reuse `Theme.*` and the custom button styles rather than hardcoding.
- LLM-facing user errors flow through `LLMError` (`LocalizedError`); views surface `error.localizedDescription`.
