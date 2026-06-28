# VocabLook

A macOS menu bar app that captures the words you look up with the native **Ctrl+Cmd+D**
and turns them into SM-2 spaced-repetition flashcards. 100% local, fully offline.

## Setup (one time)

    ./scripts/setup-signing.sh   # create a stable self-signed code-signing identity

This keeps the macOS permission grants below from breaking on every rebuild (see "Permissions").

## Run (development)

    ./scripts/run.sh           # build (debug) + bundle + launch VocabLook.app

## Permissions (required)

VocabLook needs **two** permissions in System Settings → Privacy & Security. On first launch it
requests both and opens the relevant panes — enable VocabLook in each, then relaunch:

- **Input Monitoring** — so the global `Ctrl+Cmd+D` event tap can *receive* the keypress.
  (macOS routes global keystroke monitoring through this service, not Accessibility.)
- **Accessibility** — so the app can *read the selected word* (and post the copy fallback).

Also grant **Notifications** for the daily reminder.

> If you ever see the toggle ON but capture still doesn't work, the TCC record is stale. Reset and
> re-grant: `tccutil reset Accessibility com.hoalam.vocablook && tccutil reset ListenEvent com.hoalam.vocablook`,
> then relaunch. With the stable signing identity this should not recur across rebuilds.

## Build a release

    ./scripts/run.sh release

## How it works

- `Ctrl+Cmd+D` is observed via a listen-only **CGEventTap** (a passive `NSEvent` monitor cannot see
  it — macOS consumes the combo for Look Up first). The tap does not consume it, so the native Look
  Up popover still opens.
- The selected word is read via the **Accessibility API** (`AXSelectedText`); web/Electron content
  that doesn't expose it falls back to a clipboard copy (the previous clipboard is restored).
- The surrounding sentence + source app are captured alongside the word.
- Definition/IPA come from macOS **Dictionary Services**.
- Cards are scheduled with **SM-2**; a daily notification opens the review window.
