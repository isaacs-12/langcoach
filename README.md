<div align="center">

# Lang Coach

**A local-first Korean study app for macOS, built around your own class notes.**

Import your notes, and Lang Coach turns them into flashcards, texting-style conversation
practice, and translation drills — all powered by an AI provider of your choice, with your
own API key. Everything else stays on your Mac.

<a href="https://github.com/isaacs-12/langcoach/releases/latest/download/LangCoach.zip">
  <img src="https://img.shields.io/badge/⬇%20Download%20Lang%20Coach-for%20macOS-blue?style=for-the-badge" alt="Download Lang Coach for macOS">
</a>

<img src="https://img.shields.io/badge/macOS-14%2B-lightgrey" alt="macOS 14+">
<img src="https://img.shields.io/github/v/release/isaacs-12/langcoach?label=latest" alt="Latest release">

</div>

---

## Install

1. Click the **Download** button above (it always grabs the latest release).
2. Unzip and drag **LangCoach.app** into your **Applications** folder.
3. Open it. That's it — releases are signed and notarized by Apple, so there are no
   security warnings to click through.

Lang Coach checks GitHub for new versions about once a day and offers a one-click
**Install Update** flow right inside the app. You can also check manually via
**Lang Coach → Check for Updates…**.

## Enable the AI features

Lang Coach brings its own brain — you plug in an API key from the AI provider you prefer.
The default (and cheapest to get started with) is **Google Gemini**:

1. **[Create a free Gemini API key →](https://aistudio.google.com/apikey)**
   (sign in with any Google account and click *Create API key*).
2. In Lang Coach, open **Settings (⌘,) → AI Provider**.
3. Paste the key and click **Save key**. It's stored in your macOS Keychain — never in a
   file, never synced anywhere.

Prefer another provider? Anthropic Claude ([get a key](https://console.anthropic.com/settings/keys))
and OpenAI ([get a key](https://platform.openai.com/api-keys)) work the same way — pick the
provider in Settings and paste the matching key.

> Without a key the app still opens and stores notes; the AI features (conversation,
> grading, flashcard generation, note distillation) just stay dormant until you add one.

## What does it cost?

You pay your AI provider directly for what you use — Lang Coach itself is free and adds no
markup. Costs are small: **an evening of practice on the default Gemini models typically
costs a few cents**, and Google's free tier means many casual users pay nothing at all.

Lang Coach deliberately uses **two models** so you control the cost/quality trade-off
(both are selectable in Settings):

| Setting | Used for | What changes if you upgrade/downgrade it |
|---|---|---|
| **Chat model** | Conversation practice replies | A smarter model gives more natural, nuanced Korean and better corrections. This is where quality is most noticeable. |
| **Quick-tasks model** | Grading, sentence generation, vocab extraction, note distillation | These are short, structured jobs — a cheap model does them well. Upgrading mostly just costs more. |

Approximate provider pricing (per **1 million tokens**, in/out — check the linked pages for
current numbers):

| Provider | Default chat model | Default quick model | Chat $ (in/out) | Quick $ (in/out) |
|---|---|---|---|---|
| [Google Gemini](https://ai.google.dev/pricing) | gemini-2.5-flash | gemini-2.5-flash-lite | ~$0.30 / $2.50 | ~$0.10 / $0.40 |
| [Anthropic Claude](https://claude.com/pricing#api) | claude-sonnet-4-6 | claude-haiku-4-5 | $3.00 / $15.00 | $1.00 / $5.00 |
| [OpenAI](https://openai.com/api/pricing/) | gpt-4o | gpt-4o-mini | ~$2.50 / $10.00 | ~$0.15 / $0.60 |

For scale: a full 30-message conversation session sends roughly 50k tokens in and 10k out —
about **$0.04 on Gemini defaults**, or ~$0.30 on Claude defaults. A month of daily study
usually lands between "free" and a couple of dollars on Gemini, or a few dollars on the
premium providers. Because practice context is distilled (see *study memories* below), your
notes aren't re-sent in full with every message, which keeps token usage low.

## Features

### 📚 Library — your notes, organized

- **Import from anywhere**: drag in local files (`txt`, `md`, `pdf`, `rtf`, `docx`, `doc`,
  `html`), mount local folders that stay in sync, or **connect Google Drive** and pull in
  the notes folder you share with your class.
- **Organize** notes into a folder tree, sort by date or title, and open any note in a
  dedicated, page-like reader window.

### 🧠 Study memories — how your notes power everything

When a note is imported, Lang Coach distills it once (on the cheap quick-tasks model) into
a compact **study memory**: the key vocab, grammar points, and themes. That memory — not
your full raw notes — is what gets sent along with conversation and translation practice,
so the AI stays grounded in *what you're actually learning* while keeping every request
small and cheap. Memories can be regenerated any time from the Library.

### 🃏 Flashcards — spaced repetition from your own material

Extract vocabulary from any note with one click — the AI pulls out the words worth learning
and builds cards into decks. Reviews use the classic **SM-2 spaced-repetition algorithm**
(the Anki-style *again / hard / good / easy* buttons), so cards come back right when you're
about to forget them.

### 💬 Conversation — practice texting in Korean

A messaging-style chat partner that texts with you in Korean, calibrated to your level and
seeded with your study memories, so new grammar and vocab from class actually show up in
conversation. You get gentle corrections and can keep the conversation going as long as
you like.

### ✍️ Translate — test yourself

Lang Coach generates sentences targeting the vocab and grammar from your notes; you
translate them, and the AI grades your answer with specific feedback on what was right,
what was off, and why.

## Privacy

- **Local-first**: notes, flashcards, and progress live in a local database on your Mac.
- **Keys in the Keychain**: API keys are stored only in the macOS Keychain.
- **Two network destinations, both yours**: the AI provider you configured, and (only if
  you connect it) Google Drive with read-only scope. There is no telemetry, no account,
  and no server of ours.
- **Sandboxed**: the app runs in the macOS App Sandbox with access only to files you
  explicitly select.

## Building from source

```bash
git clone https://github.com/isaacs-12/langcoach.git
cd langcoach
make run        # build (Debug, unsigned) and launch
```

Requirements: macOS 14+, Xcode 16+. `make help` lists all developer commands.
Maintainers cut releases with `make release` (see `scripts/release.sh` for the one-time
signing/notarization setup).

## Contributing

Issues and pull requests are welcome — especially bug reports, Korean-learning feature
ideas, and support for more note formats or languages.

## License

The Lang Coach source code is licensed under the **[Apache License 2.0](LICENSE)** — you're
free to use, modify, and redistribute it, including in commercial and closed-source projects,
subject to the license terms (which include an explicit patent grant).

A few clarifications:

- **The "Lang Coach" name and app icon are not covered by the code license.** They're
  reserved so that redistributed or forked builds don't impersonate the official app. If you
  ship your own build from this source, please give it a different name and icon. Official,
  signed releases are built and distributed only from this repository.
- **Any hosted or paid service** offered by the maintainers (for example, a future
  subscription that proxies AI requests) is a **separate product and is not part of this
  Apache-licensed source.** The app in this repository remains free and bring-your-own-key.

---

<div align="center">Made by Isaac Smith · © 2026 · Licensed under Apache-2.0</div>
