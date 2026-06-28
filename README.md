# VocabLook

A macOS menu bar app that captures the words you look up with the native **Ctrl+Cmd+D**
and turns them into SM-2 spaced-repetition flashcards. 100% local, fully offline.

## Run (development)

    ./scripts/run.sh           # build (debug) + bundle + launch VocabLook.app

Grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility),
then relaunch. Grant **Notifications** for the daily reminder.

## Build a release

    ./scripts/run.sh release

## How it works

- `Ctrl+Cmd+D` is observed (not consumed) — the native Look Up still opens.
- The selected word + surrounding sentence + source app are captured via the Accessibility API.
- Definition/IPA come from macOS Dictionary Services.
- Cards are scheduled with SM-2; a daily notification opens the review window.
