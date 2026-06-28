# VocabLook — Design Spec

- **Date:** 2026-06-28
- **Status:** Approved (design), pending implementation plan
- **Platform:** macOS (native), menu bar app
- **Stack:** Swift + SwiftUI
- **UI mockups:** `docs/vocablook-mockups.html` (also published as an Artifact)

## 1. Purpose

A macOS menu bar app that turns the words you look up while reading into spaced-repetition
flashcards, with zero change to your habits. You keep using the native macOS Look Up shortcut
(`Ctrl + Cmd + D`); VocabLook listens, captures the word together with the sentence you found it
in, and serves it back the next day — then on an adapting SM-2 schedule.

**Problem it solves:** macOS Dictionary.app keeps no accessible lookup history. Words you look up
are forgotten minutes later. VocabLook creates that history and reinforces it.

## 2. Constraints & key technical decisions

- **No public lookup-history API.** macOS Dictionary.app does not expose what the user has looked
  up. We therefore *generate* the history by observing the lookup action ourselves.
- **Keep the native shortcut.** The user explicitly wants to keep pressing `Ctrl + Cmd + D`. We use
  an **observe-only global event monitor** (`NSEvent.addGlobalMonitorForEvents`) so the event is NOT
  consumed — the system Look Up popover still opens normally.
- **Capture mechanism.** On detecting `Ctrl+Cmd+D`, read the focused UI element's `AXSelectedText`
  via the **Accessibility API**. Fallback for apps that don't expose it (some Electron/web views):
  synthesize a copy and read the pasteboard, restoring the previous pasteboard contents afterward.
- **Definitions.** Use macOS **Dictionary Services** (`DCSCopyTextDefinition`) for definition + IPA.
- **Privacy.** 100% local, fully offline. No network in the MVP. This is a deliberate selling point.
- **Permissions.** Requires Accessibility (TCC) — granted once via honest onboarding.
  Requires Notifications permission for the daily reminder.
- **No unit tests by default** (per user preference); verify via build + manual runs.

## 3. Architecture

A single SwiftUI menu bar app (`LSUIElement` / `MenuBarExtra`), composed of focused components that
communicate through well-defined interfaces:

| Component | Responsibility | Depends on |
|---|---|---|
| `HotkeyMonitor` | Observe-only global monitor for `Ctrl+Cmd+D`; emits a "lookup happened" event. Does not consume the event. | AppKit `NSEvent` |
| `LookupCapturer` | On event, read `AXSelectedText` of the focused element; extract the word/phrase, the surrounding sentence (context), the front-most app name. Fallback to pasteboard-copy when AX text is empty. | Accessibility API |
| `DefinitionService` | Given a term, return `{ definition, partOfSpeech, ipa }`. | `DCSCopyTextDefinition` |
| `Store` | Persist and query `Entry`, `Card`, `ReviewLog`. Local SQLite. | GRDB (or SwiftData) |
| `SRSEngine` | Pure scheduling logic: given a card's state + a grade, return the next state (ease, interval, due date). SM-2. | — (pure, no I/O) |
| `ReviewSession` | Drives a review: fetch due cards, present front→back, apply grade via `SRSEngine`, write `ReviewLog`. | `Store`, `SRSEngine` |
| `Reminder` | Schedule one local notification/day at the chosen time; compute due count; update menu-bar badge. | `UserNotifications` |
| `MenuBarUI` | Status item + popover: due count, streak, recent captures, entry to review/settings. | SwiftUI |
| `ReviewUI` | Flashcard window: front (word/IPA/pronounce), revealed (definition/context), grade buttons + keys 1–4. | SwiftUI, `ReviewSession` |
| `OnboardingUI` | First-run Accessibility + Notifications permission flow. | — |
| `SettingsUI` | Reminder time, daily goal, pronounce-on-reveal, launch-at-login. | `ServiceManagement` |
| `Pronouncer` | Speak a word via system TTS. | `AVSpeechSynthesizer` |

**Design for isolation:** `SRSEngine` is pure (fully testable/reasoned in isolation); `Store` hides
persistence behind query methods; UI never touches the Accessibility/Dictionary APIs directly.

## 4. Data model

```
Entry
  id            UUID
  term          String        // the word or phrase looked up
  normalized    String        // lowercased/trimmed key for dedup
  definition    String?
  partOfSpeech  String?
  ipa           String?
  contextText   String?       // the sentence the term appeared in
  sourceApp     String?       // e.g. "Safari"
  sourceDetail  String?       // e.g. window/document title when available
  createdAt     Date

Card  (one per Entry)
  id            UUID
  entryId       UUID
  easeFactor    Double        // SM-2, starts 2.5
  intervalDays  Int           // current interval
  repetitions   Int           // consecutive correct
  dueAt         Date          // first card created due = tomorrow (local day)
  lapses        Int

ReviewLog
  id            UUID
  cardId        UUID
  grade         Int           // 0 Again, 1 Hard, 2 Good, 3 Easy
  reviewedAt    Date
  prevInterval  Int
  newInterval   Int
```

**Dedup:** on capture, if an `Entry` with the same `normalized` term exists, do not create a second
card; bump a "seen again" signal on the existing entry (kept minimal in MVP — just avoid duplicates).

## 5. Data flow

**Capture (background):**
`Ctrl+Cmd+D` → `HotkeyMonitor` fires → `LookupCapturer` reads selected text + context + source app →
`DefinitionService` fetches definition/IPA → `Store` upserts `Entry`, creates `Card` (dueAt =
start of tomorrow, local) → Capture HUD shows "Saved <term>" with Undo (~2s).

**Daily review:**
`Reminder` fires one notification at the chosen time showing the due count → user clicks (or opens
popover → "Start review") → `ReviewSession` loads cards where `dueAt <= now` → for each: show front,
reveal on Space, user grades (keys 1–4 / buttons) → `SRSEngine` computes next state → `Store`
updates `Card` + appends `ReviewLog` → streak updated when a session completes.

## 6. SRS scheduling (SM-2)

- Grades: `0 Again`, `1 Hard`, `2 Good`, `3 Easy`.
- New card: first review due **tomorrow** (local day boundary), per the user's original ask.
- On grade:
  - `Again`: repetitions → 0, interval → ~1 min (relearn same session), ease −0.20 (floor 1.3), lapse++.
  - `Hard`: interval × 1.2, ease −0.15.
  - `Good`: standard SM-2 progression (1 → 6 → interval×ease …).
  - `Easy`: standard × easy bonus (1.3), ease +0.15.
- The four grade buttons show a **live preview** of the resulting interval (as in the mockup).
- Daily goal caps how many **new** cards enter review per day (default 20); due reviews are not capped.

## 7. Screens (per approved mockups)

1. **Menu bar popover** — due-today count, streak, "Start review", today's recent captures (term ·
   source · time), totals (new today / total learned / recall %), footer: History, Settings.
2. **Capture HUD** — transient confirmation toast with Undo; never steals focus.
3. **Flashcard review** — front (serif headword, IPA, pronounce button, source chip) → revealed
   (definition, context sentence with the term highlighted) → grade row (Again/Hard/Good/Easy with
   interval previews). Keyboard: Space reveals, 1–4 grade.
4. **Daily notification** — due count + streak nudge + "Review now".
5. **Onboarding** — explains and links to Accessibility settings; tests capture.
6. **Settings** — capture shortcut (display only, mirrors system), reminder time, daily goal,
   pronounce-on-reveal, launch-at-login.

**Visual identity:** ink-indigo accent (`#5B5BD6`), New York serif for headwords (dictionary feel),
SF Pro for chrome, SF Mono for IPA/data, macOS vibrancy + traffic-light windows (HIG-native).

## 8. Error handling & edge cases

- **No selected text / unsupported app:** if both AX read and copy-fallback yield empty, show a brief
  "Couldn't read the selection" HUD and log nothing. Never crash, never create empty entries.
- **No dictionary definition found:** still save the `Entry` (term + context) with `definition = nil`;
  the card is reviewable as a recall prompt.
- **Permission not granted:** capture silently no-ops and the menu bar shows a "Grant Accessibility"
  prompt; re-open onboarding on click.
- **Pasteboard fallback:** snapshot and restore the user's previous pasteboard contents.
- **Duplicate lookups:** dedup by normalized term (see §4) — no duplicate cards.
- **Day boundary:** "tomorrow" and streak use the local calendar day, not 24h offsets.

## 9. Scope

### MVP (v1) — what we build now
- `Ctrl+Cmd+D` observe-only capture (term + context sentence + source app + IPA + definition).
- Local-only SQLite storage, fully offline.
- SM-2 spaced repetition with first-review-tomorrow.
- Menu bar popover, capture HUD, flashcard review window, onboarding, settings.
- Daily notification + streak.
- Pronounce via system TTS.

### Later (designed-for, deferred)
- Fill-in-the-blank cards from the captured sentence; def→word & multiple-choice card types.
- Leech detection; auto tags/decks by source or topic.
- Vietnamese gloss via Apple Translate.
- Weekly summary & retention stats; History/search view (basic stub in MVP footer).
- Export to Anki (.apkg) / CSV; iCloud sync.
- AI examples, mnemonics, and "story from today's words" via Claude API.

### Explicitly out of scope (YAGNI for v1)
- Accounts, cloud backend, mobile/iOS app, multi-language UI.

## 10. Verification (no unit tests by default)

- Build the app and run it.
- Manual capture test: select text in Safari/Books/Notes, press `Ctrl+Cmd+D`, confirm HUD + entry.
- Manual review test: create cards, advance the clock / due date, run a review session, confirm
  SM-2 intervals and streak update.
- `SRSEngine` is pure and may get lightweight tests later if scheduling bugs appear.
