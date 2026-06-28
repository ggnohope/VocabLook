# VocabLook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that captures words looked up via the system `Ctrl+Cmd+D` shortcut and reviews them as SM-2 spaced-repetition flashcards.

**Architecture:** A single SwiftUI `MenuBarExtra` app (LSUIElement). An observe-only global key monitor detects `Ctrl+Cmd+D`; the Accessibility API reads the selected word + surrounding sentence; Dictionary Services provides the definition/IPA; everything persists to a local SQLite DB via GRDB. A pure `SRSEngine` schedules reviews; a daily notification opens the flashcard window.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, GRDB (SQLite), Accessibility API (`AXUIElement`), Dictionary Services (`DCSCopyTextDefinition`), `UserNotifications`, `AVSpeechSynthesizer`, Swift Package Manager + a bundling script that produces `VocabLook.app`.

**Verification policy:** Per project preference, no unit-test target by default. Each task is verified by `swift build` succeeding plus the manual checks listed. Re-bundle and relaunch `VocabLook.app` to test runtime behavior. `SRSEngine` is pure — Task 4 includes an *optional* test target you may enable later.

**Important runtime note:** `UNUserNotificationCenter` and stable TCC (Accessibility) identity require a real `.app` bundle, not the bare SPM binary. Always run via `scripts/run.sh` (build → bundle → ad-hoc sign → launch). After each rebuild you may need to re-grant Accessibility (ad-hoc signing changes the code hash); this is expected in dev.

---

## File Structure

```
VocabLook/
  Package.swift
  scripts/
    Info.plist                  # bundle metadata: LSUIElement, usage strings, bundle id
    bundle-app.sh               # assemble VocabLook.app from the built binary
    run.sh                      # build + bundle + sign + launch
  Sources/VocabLook/
    VocabLookApp.swift          # @main: MenuBarExtra + Window scenes + AppDelegate
    AppDelegate.swift           # lifecycle, starts CaptureCoordinator + Reminder
    Models/
      Grade.swift               # enum Grade (again/hard/good/easy)
      Entry.swift               # GRDB record: a looked-up term
      Card.swift                # GRDB record: SRS state for an entry
      ReviewLog.swift           # GRDB record: a single graded review
    Persistence/
      Store.swift               # GRDB setup, migrations, all queries
    SRS/
      SRSEngine.swift           # pure SM-2 scheduler
    Capture/
      HotkeyMonitor.swift       # observe-only global Ctrl+Cmd+D monitor
      LookupCapturer.swift      # AX selected text + context + source app
      DefinitionService.swift   # DCSCopyTextDefinition wrapper + IPA parse
      CaptureCoordinator.swift  # wires monitor -> capturer -> definition -> store -> HUD
    Services/
      Permissions.swift         # AX trust check/prompt, notification auth
      Settings.swift            # UserDefaults-backed preferences
      AppState.swift            # ObservableObject: dueCount, streak, totals, recents
      Pronouncer.swift          # AVSpeechSynthesizer wrapper
      Reminder.swift            # daily local notification + due count
      LaunchAtLogin.swift       # SMAppService login item toggle
      ReviewSession.swift       # drives a review (due cards -> grade -> persist)
    UI/
      MenuBarContentView.swift  # popover content
      ReviewView.swift          # flashcard front/back + grades
      CaptureHUD.swift          # borderless NSPanel "Saved <term>" toast
      HUDController.swift        # shows/hides the HUD panel
      OnboardingView.swift      # Accessibility/notification permission flow
      SettingsView.swift        # preferences window
```

---

## Task 1: Scaffold the SPM package and a launching menu bar app

**Files:**
- Create: `Package.swift`
- Create: `scripts/Info.plist`
- Create: `scripts/bundle-app.sh`
- Create: `scripts/run.sh`
- Create: `Sources/VocabLook/VocabLookApp.swift`
- Create: `Sources/VocabLook/AppDelegate.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VocabLook",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "VocabLook",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        )
    ]
)
```

- [ ] **Step 2: Create `scripts/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>VocabLook</string>
    <key>CFBundleDisplayName</key><string>VocabLook</string>
    <key>CFBundleIdentifier</key><string>com.hoalam.vocablook</string>
    <key>CFBundleExecutable</key><string>VocabLook</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `scripts/bundle-app.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
APP="VocabLook.app"
BIN=".build/${CONFIG}/VocabLook"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/VocabLook"
# Ad-hoc sign so TCC has an identity to track.
codesign --force --deep --sign - "$APP"
echo "Bundled $APP ($CONFIG)"
```

- [ ] **Step 4: Create `scripts/run.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build $([ "$CONFIG" = "release" ] && echo "-c release")
./scripts/bundle-app.sh "$CONFIG"
# Quit any running instance, then launch fresh.
pkill -x VocabLook 2>/dev/null || true
open VocabLook.app
echo "Launched VocabLook.app"
```

- [ ] **Step 5: Create `Sources/VocabLook/VocabLookApp.swift`**

```swift
import SwiftUI

@main
struct VocabLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("VocabLook", systemImage: "book.closed") {
            Text("VocabLook is running")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 6: Create `Sources/VocabLook/AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 7: Make scripts executable and build**

Run: `chmod +x scripts/*.sh && swift build`
Expected: dependencies resolve, build succeeds (`Compiling ... Build complete!`).

- [ ] **Step 8: Run and verify the menu bar icon appears**

Run: `./scripts/run.sh`
Expected: a book icon appears in the macOS menu bar; clicking it shows "VocabLook is running". No Dock icon (LSUIElement).

- [ ] **Step 9: Commit**

```bash
git add Package.swift scripts Sources
git commit -m "feat: scaffold SPM menu bar app with bundling scripts"
```

---

## Task 2: Domain models and settings

**Files:**
- Create: `Sources/VocabLook/Models/Grade.swift`
- Create: `Sources/VocabLook/Models/Entry.swift`
- Create: `Sources/VocabLook/Models/Card.swift`
- Create: `Sources/VocabLook/Models/ReviewLog.swift`
- Create: `Sources/VocabLook/Services/Settings.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Models/Grade.swift`**

```swift
import Foundation

enum Grade: Int, CaseIterable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}
```

- [ ] **Step 2: Create `Sources/VocabLook/Models/Entry.swift`**

```swift
import Foundation
import GRDB

struct Entry: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var term: String
    var normalized: String
    var definition: String?
    var partOfSpeech: String?
    var ipa: String?
    var contextText: String?
    var sourceApp: String?
    var sourceDetail: String?
    var createdAt: Date

    static let databaseTableName = "entry"

    static func normalize(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
```

- [ ] **Step 3: Create `Sources/VocabLook/Models/Card.swift`**

```swift
import Foundation
import GRDB

struct Card: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var entryId: String
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueAt: Date
    var lapses: Int

    static let databaseTableName = "card"

    /// Default state for a freshly captured word: first review tomorrow.
    static func fresh(entryId: String, now: Date, calendar: Calendar = .current) -> Card {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return Card(id: UUID().uuidString, entryId: entryId, easeFactor: 2.5,
                    intervalDays: 1, repetitions: 0, dueAt: tomorrow, lapses: 0)
    }
}
```

- [ ] **Step 4: Create `Sources/VocabLook/Models/ReviewLog.swift`**

```swift
import Foundation
import GRDB

struct ReviewLog: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var cardId: String
    var grade: Int
    var reviewedAt: Date
    var prevInterval: Int
    var newInterval: Int

    static let databaseTableName = "reviewLog"
}
```

- [ ] **Step 5: Create `Sources/VocabLook/Services/Settings.swift`**

```swift
import Foundation

/// UserDefaults-backed preferences. Single source of truth for user settings + streak.
enum Settings {
    private static let d = UserDefaults.standard

    enum Key {
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let dailyGoal = "dailyGoal"
        static let pronounceOnReveal = "pronounceOnReveal"
        static let streakCount = "streakCount"
        static let lastReviewDay = "lastReviewDay"   // yyyy-MM-dd string
        static let didOnboard = "didOnboard"
    }

    static var reminderHour: Int { get { d.object(forKey: Key.reminderHour) as? Int ?? 20 } set { d.set(newValue, forKey: Key.reminderHour) } }
    static var reminderMinute: Int { get { d.object(forKey: Key.reminderMinute) as? Int ?? 30 } set { d.set(newValue, forKey: Key.reminderMinute) } }
    static var dailyGoal: Int { get { d.object(forKey: Key.dailyGoal) as? Int ?? 20 } set { d.set(newValue, forKey: Key.dailyGoal) } }
    static var pronounceOnReveal: Bool { get { d.bool(forKey: Key.pronounceOnReveal) } set { d.set(newValue, forKey: Key.pronounceOnReveal) } }
    static var streakCount: Int { get { d.integer(forKey: Key.streakCount) } set { d.set(newValue, forKey: Key.streakCount) } }
    static var lastReviewDay: String? { get { d.string(forKey: Key.lastReviewDay) } set { d.set(newValue, forKey: Key.lastReviewDay) } }
    static var didOnboard: Bool { get { d.bool(forKey: Key.didOnboard) } set { d.set(newValue, forKey: Key.didOnboard) } }
}
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 7: Commit**

```bash
git add Sources/VocabLook/Models Sources/VocabLook/Services/Settings.swift
git commit -m "feat: add domain models and settings"
```

---

## Task 3: Persistence layer (GRDB Store)

**Files:**
- Create: `Sources/VocabLook/Persistence/Store.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Persistence/Store.swift`**

```swift
import Foundation
import GRDB

/// Owns the SQLite database and exposes all queries. Thread-safe via DatabaseQueue.
final class Store {
    static let shared = try! Store()

    private let dbQueue: DatabaseQueue

    init() throws {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("VocabLook", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("vocablook.sqlite").path)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "entry") { t in
                t.column("id", .text).primaryKey()
                t.column("term", .text).notNull()
                t.column("normalized", .text).notNull().indexed()
                t.column("definition", .text)
                t.column("partOfSpeech", .text)
                t.column("ipa", .text)
                t.column("contextText", .text)
                t.column("sourceApp", .text)
                t.column("sourceDetail", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "card") { t in
                t.column("id", .text).primaryKey()
                t.column("entryId", .text).notNull().references("entry", onDelete: .cascade)
                t.column("easeFactor", .double).notNull()
                t.column("intervalDays", .integer).notNull()
                t.column("repetitions", .integer).notNull()
                t.column("dueAt", .datetime).notNull().indexed()
                t.column("lapses", .integer).notNull()
            }
            try db.create(table: "reviewLog") { t in
                t.column("id", .text).primaryKey()
                t.column("cardId", .text).notNull().references("card", onDelete: .cascade)
                t.column("grade", .integer).notNull()
                t.column("reviewedAt", .datetime).notNull()
                t.column("prevInterval", .integer).notNull()
                t.column("newInterval", .integer).notNull()
            }
        }
        return m
    }

    // MARK: - Capture

    /// Returns true if a brand-new entry+card was created; false if it was a duplicate.
    @discardableResult
    func saveLookup(term: String, definition: String?, partOfSpeech: String?, ipa: String?,
                    context: String?, sourceApp: String?, sourceDetail: String?, now: Date) throws -> Entry {
        let normalized = Entry.normalize(term)
        return try dbQueue.write { db in
            if let existing = try Entry.filter(Column("normalized") == normalized).fetchOne(db) {
                return existing
            }
            var entry = Entry(id: UUID().uuidString, term: term, normalized: normalized,
                              definition: definition, partOfSpeech: partOfSpeech, ipa: ipa,
                              contextText: context, sourceApp: sourceApp, sourceDetail: sourceDetail,
                              createdAt: now)
            try entry.insert(db)
            var card = Card.fresh(entryId: entry.id, now: now)
            try card.insert(db)
            return entry
        }
    }

    func deleteEntry(id: String) throws {
        _ = try dbQueue.write { db in try Entry.deleteOne(db, key: id) }
    }

    // MARK: - Review

    /// Cards due at or before `now`, paired with their entry, oldest-due first.
    func dueCards(now: Date, limit: Int = 500) throws -> [(card: Card, entry: Entry)] {
        try dbQueue.read { db in
            let cards = try Card.filter(Column("dueAt") <= now)
                .order(Column("dueAt").asc)
                .limit(limit)
                .fetchAll(db)
            return try cards.compactMap { card in
                guard let entry = try Entry.fetchOne(db, key: card.entryId) else { return nil }
                return (card, entry)
            }
        }
    }

    func updateCard(_ card: Card) throws {
        try dbQueue.write { db in try card.update(db) }
    }

    func appendLog(_ log: ReviewLog) throws {
        try dbQueue.write { db in var l = log; try l.insert(db) }
    }

    // MARK: - Stats for the popover

    func dueCount(now: Date) throws -> Int {
        try dbQueue.read { db in try Card.filter(Column("dueAt") <= now).fetchCount(db) }
    }

    func capturedToday(now: Date, calendar: Calendar = .current) throws -> Int {
        let start = calendar.startOfDay(for: now)
        return try dbQueue.read { db in try Entry.filter(Column("createdAt") >= start).fetchCount(db) }
    }

    func totalEntries() throws -> Int {
        try dbQueue.read { db in try Entry.fetchCount(db) }
    }

    func recentEntries(limit: Int = 6) throws -> [Entry] {
        try dbQueue.read { db in
            try Entry.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }

    /// Recall % = good/easy reviews over total reviews, all time. Returns nil if no reviews yet.
    func recallPercent() throws -> Int? {
        try dbQueue.read { db in
            let total = try ReviewLog.fetchCount(db)
            guard total > 0 else { return nil }
            let good = try ReviewLog.filter(Column("grade") >= Grade.good.rawValue).fetchCount(db)
            return Int((Double(good) / Double(total) * 100).rounded())
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Manual smoke check (temporary)**

Add this line temporarily to `AppDelegate.applicationDidFinishLaunching`, run `./scripts/run.sh`, confirm no crash, then remove it:

```swift
print("Store ready, total entries:", (try? Store.shared.totalEntries()) ?? -1)
```
Expected: log prints `Store ready, total entries: 0` (view via Console.app, filter "VocabLook"). Remove the line after verifying.

- [ ] **Step 4: Commit**

```bash
git add Sources/VocabLook/Persistence/Store.swift
git commit -m "feat: add GRDB store with schema, capture, review and stats queries"
```

---

## Task 4: Pure SM-2 scheduler

**Files:**
- Create: `Sources/VocabLook/SRS/SRSEngine.swift`

- [ ] **Step 1: Create `Sources/VocabLook/SRS/SRSEngine.swift`**

```swift
import Foundation

/// Pure SM-2 scheduler. No I/O — given a card and a grade, returns the next card state.
enum SRSEngine {
    static let minEase = 1.3
    static let easyBonus = 1.3

    /// Compute the next card state after grading. `now` is the review time.
    static func schedule(_ card: Card, grade: Grade, now: Date, calendar: Calendar = .current) -> Card {
        var c = card
        let day = 86_400.0

        switch grade {
        case .again:
            c.repetitions = 0
            c.lapses += 1
            c.easeFactor = max(minEase, c.easeFactor - 0.20)
            c.intervalDays = 0
            c.dueAt = now.addingTimeInterval(60) // ~1 minute, relearn this session
            return c

        case .hard:
            c.easeFactor = max(minEase, c.easeFactor - 0.15)
            c.intervalDays = max(1, Int((Double(max(card.intervalDays, 1)) * 1.2).rounded()))

        case .good:
            switch c.repetitions {
            case 0: c.intervalDays = 1
            case 1: c.intervalDays = 6
            default: c.intervalDays = max(1, Int((Double(card.intervalDays) * c.easeFactor).rounded()))
            }

        case .easy:
            c.easeFactor = c.easeFactor + 0.15
            switch c.repetitions {
            case 0: c.intervalDays = Int((1 * easyBonus).rounded())
            case 1: c.intervalDays = Int((6 * easyBonus).rounded())
            default: c.intervalDays = max(1, Int((Double(card.intervalDays) * c.easeFactor * easyBonus).rounded()))
            }
        }

        if grade != .again { c.repetitions += 1 }
        c.dueAt = now.addingTimeInterval(Double(c.intervalDays) * day)
        return c
    }

    /// Human-readable interval preview for a grade button (e.g. "<1 min", "2 days").
    static func preview(_ card: Card, grade: Grade, now: Date) -> String {
        let next = schedule(card, grade: grade, now: now)
        let seconds = next.dueAt.timeIntervalSince(now)
        if seconds < 3600 { return "<1 min" }
        let days = Int((seconds / 86_400).rounded())
        if days <= 1 { return "1 day" }
        if days < 30 { return "\(days) days" }
        let months = Int((Double(days) / 30).rounded())
        return months <= 1 ? "1 mo" : "\(months) mo"
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: (Optional) enable a test target for the scheduler**

Per project preference, tests are skipped by default. If you later want to lock the SM-2 math, add to `Package.swift` a `.testTarget(name: "VocabLookTests", dependencies: ["VocabLook"])`, create `Tests/VocabLookTests/SRSEngineTests.swift` asserting: a fresh card graded `.good` → interval 1; graded again `.good` → 6; `.again` → due within ~60s and lapses incremented; `.easy` raises ease above 2.5. Run `swift test`.

- [ ] **Step 4: Commit**

```bash
git add Sources/VocabLook/SRS/SRSEngine.swift
git commit -m "feat: add pure SM-2 scheduler with interval previews"
```

---

## Task 5: Dictionary definition service

**Files:**
- Create: `Sources/VocabLook/Capture/DefinitionService.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Capture/DefinitionService.swift`**

```swift
import Foundation
import CoreServices

struct DictionaryResult {
    var definition: String?
    var partOfSpeech: String?
    var ipa: String?
}

/// Wraps macOS Dictionary Services. Best-effort parsing of the plain-text entry.
enum DefinitionService {
    static func define(_ term: String) -> DictionaryResult {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DictionaryResult() }

        let range = CFRangeMake(0, trimmed.utf16.count)
        guard let unmanaged = DCSCopyTextDefinition(nil, trimmed as CFString, range) else {
            return DictionaryResult()
        }
        let full = unmanaged.takeRetainedValue() as String
        return DictionaryResult(definition: cleanDefinition(full, term: trimmed),
                                partOfSpeech: parsePartOfSpeech(full),
                                ipa: parseIPA(full))
    }

    /// The dictionary text starts with the headword; trim it and collapse whitespace.
    private static func cleanDefinition(_ text: String, term: String) -> String? {
        var s = text
        if s.lowercased().hasPrefix(term.lowercased()) {
            s = String(s.dropFirst(term.count))
        }
        s = s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : String(s.prefix(400))
    }

    /// IPA is typically delimited by pipes, e.g. "ephemeral | əˈfem(ə)rəl |".
    private static func parseIPA(_ text: String) -> String? {
        let parts = text.components(separatedBy: "|")
        guard parts.count >= 2 else { return nil }
        let candidate = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    private static func parsePartOfSpeech(_ text: String) -> String? {
        for pos in ["noun", "verb", "adjective", "adverb", "pronoun",
                    "preposition", "conjunction", "interjection", "determiner"] {
            if text.range(of: "\\b\(pos)\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                return pos
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Manual check (temporary)**

Temporarily add to `applicationDidFinishLaunching`, run `./scripts/run.sh`, check Console.app, then remove:

```swift
let r = DefinitionService.define("ephemeral")
print("DEF:", r.definition ?? "nil", "| IPA:", r.ipa ?? "nil", "| POS:", r.partOfSpeech ?? "nil")
```
Expected: a definition string for "ephemeral", an IPA like `əˈfem(ə)rəl`, POS `adjective`. (If the system has no English dictionary enabled in Dictionary.app, definition may be nil — enable one in Dictionary.app › Settings.) Remove the line after verifying.

- [ ] **Step 4: Commit**

```bash
git add Sources/VocabLook/Capture/DefinitionService.swift
git commit -m "feat: add Dictionary Services definition/IPA lookup"
```

---

## Task 6: Permissions helper

**Files:**
- Create: `Sources/VocabLook/Services/Permissions.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Services/Permissions.swift`**

```swift
import AppKit
import ApplicationServices
import UserNotifications

enum Permissions {
    /// Whether the app is trusted for Accessibility (needed for global key monitor + AX reads).
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts for Accessibility access (shows the system dialog) and returns the current state.
    @discardableResult
    static func promptAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly at the Accessibility pane.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func requestNotifications(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/VocabLook/Services/Permissions.swift
git commit -m "feat: add accessibility and notification permission helpers"
```

---

## Task 7: Observe-only global hotkey monitor

**Files:**
- Create: `Sources/VocabLook/Capture/HotkeyMonitor.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Capture/HotkeyMonitor.swift`**

```swift
import AppKit

/// Observes Ctrl+Cmd+D system-wide WITHOUT consuming it, so the native Look Up still opens.
final class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let keyCodeD: UInt16 = 0x02 // ANSI 'D'

    /// Called on the main thread when Ctrl+Cmd+D is pressed.
    var onLookup: (() -> Void)?

    func start() {
        // Global monitor: fires when another app is frontmost (the common case).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        // Local monitor: fires when one of our own windows is focused. Returns the event so it isn't swallowed.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.control, .command], event.keyCode == keyCodeD else { return }
        DispatchQueue.main.async { [weak self] in self?.onLookup?() }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/VocabLook/Capture/HotkeyMonitor.swift
git commit -m "feat: add observe-only Ctrl+Cmd+D global monitor"
```

---

## Task 8: Lookup capturer (selected text + context + source)

**Files:**
- Create: `Sources/VocabLook/Capture/LookupCapturer.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Capture/LookupCapturer.swift`**

```swift
import AppKit
import ApplicationServices

struct CapturedLookup {
    var term: String
    var context: String?
    var sourceApp: String?
    var sourceDetail: String?
}

/// Reads the currently selected text (the word being looked up) via the Accessibility API,
/// plus the surrounding sentence and the frontmost app. Falls back to a pasteboard copy.
final class LookupCapturer {

    func capture() -> CapturedLookup? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let sourceApp = frontApp?.localizedName

        if let element = focusedElement() {
            if let selected = selectedText(of: element),
               !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let context = surroundingSentence(of: element, selected: selected)
                return CapturedLookup(term: clean(selected), context: context,
                                      sourceApp: sourceApp, sourceDetail: windowTitle(of: element))
            }
        }
        return copyFallback(sourceApp: sourceApp)
    }

    // MARK: - Accessibility reads

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success
        else { return nil }
        return (value as! AXUIElement)
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// Best-effort: read the full text + selected range, then expand to sentence boundaries.
    private func surroundingSentence(of element: AXUIElement, selected: String) -> String? {
        var fullValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullValue) == .success,
              let full = fullValue as? String, !full.isEmpty else { return nil }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success
        else { return sentenceFallback(in: full, containing: selected) }

        var cfRange = CFRange()
        if AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange), cfRange.location != kCFNotFound {
            let ns = full as NSString
            let loc = min(max(cfRange.location, 0), ns.length)
            return sentence(in: full, atUTF16Offset: loc)
        }
        return sentenceFallback(in: full, containing: selected)
    }

    private func sentence(in text: String, atUTF16Offset offset: Int) -> String? {
        let ns = text as NSString
        var start = offset, end = offset
        let terminators = CharacterSet(charactersIn: ".!?\n")
        while start > 0 {
            let ch = ns.substring(with: NSRange(location: start - 1, length: 1))
            if ch.rangeOfCharacter(from: terminators) != nil { break }
            start -= 1
        }
        while end < ns.length {
            let ch = ns.substring(with: NSRange(location: end, length: 1))
            end += 1
            if ch.rangeOfCharacter(from: terminators) != nil { break }
        }
        let s = ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func sentenceFallback(in text: String, containing selected: String) -> String? {
        guard let r = text.range(of: selected) else { return nil }
        let offset = text.distance(from: text.startIndex, to: r.lowerBound)
        let utf16Offset = (text as NSString).length == text.count ? offset
            : (String(text[..<r.lowerBound]) as NSString).length
        return sentence(in: text, atUTF16Offset: utf16Offset)
    }

    private func windowTitle(of element: AXUIElement) -> String? {
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &win) == .success
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }

    // MARK: - Pasteboard fallback

    private func copyFallback(sourceApp: String?) -> CapturedLookup? {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let beforeCount = pb.changeCount

        sendCopy()

        // Poll briefly for the target app to update the pasteboard.
        var copied: String?
        for _ in 0..<20 {
            if pb.changeCount != beforeCount { copied = pb.string(forType: .string); break }
            usleep(10_000) // 10ms
        }

        // Restore the user's previous pasteboard contents.
        pb.clearContents()
        if let previous { pb.setString(previous, forType: .string) }

        guard let text = copied?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return CapturedLookup(term: clean(text), context: nil, sourceApp: sourceApp, sourceDetail: nil)
    }

    private func sendCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'C'
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cmdUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    /// Keep only the first ~6 words so a stray paragraph selection still yields a reasonable term.
    private func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count > 6 ? words.prefix(6).joined(separator: " ") : trimmed
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/VocabLook/Capture/LookupCapturer.swift
git commit -m "feat: add accessibility-based lookup capturer with copy fallback"
```

---

## Task 9: Capture HUD and capture coordinator

**Files:**
- Create: `Sources/VocabLook/UI/CaptureHUD.swift`
- Create: `Sources/VocabLook/UI/HUDController.swift`
- Create: `Sources/VocabLook/Capture/CaptureCoordinator.swift`

- [ ] **Step 1: Create `Sources/VocabLook/UI/CaptureHUD.swift`**

```swift
import SwiftUI

/// The "Saved <term>" toast content. Pure view; the panel is managed by HUDController.
struct CaptureHUD: View {
    let term: String
    let subtitle: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Color.green)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Saved ").font(.system(size: 14)) + Text(term).font(.system(size: 14, weight: .semibold, design: .serif))
                Text(subtitle).font(.system(size: 11.5)).foregroundColor(.secondary)
            }

            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 2: Create `Sources/VocabLook/UI/HUDController.swift`**

```swift
import AppKit
import SwiftUI

/// Shows a borderless, non-activating floating panel near the bottom of the active screen.
final class HUDController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(term: String, subtitle: String, onUndo: @escaping () -> Void) {
        dismiss()

        let hud = CaptureHUD(term: term, subtitle: subtitle) { [weak self] in
            onUndo()
            self?.dismiss()
        }
        let hosting = NSHostingView(rootView: hud)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 60)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 160
            let y = frame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
```

- [ ] **Step 3: Create `Sources/VocabLook/Capture/CaptureCoordinator.swift`**

```swift
import AppKit

/// Glues the hotkey monitor to capture → definition → store → HUD. Notifies AppState on success.
final class CaptureCoordinator {
    private let monitor = HotkeyMonitor()
    private let capturer = LookupCapturer()
    private let hud = HUDController()
    private let store: Store
    private let appState: AppState

    init(store: Store = .shared, appState: AppState) {
        self.store = store
        self.appState = appState
    }

    func start() {
        monitor.onLookup = { [weak self] in self?.handleLookup() }
        monitor.start()
    }

    func stop() { monitor.stop() }

    private func handleLookup() {
        // Give the OS a beat to finalize the selection the user is looking up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            guard let captured = self.capturer.capture() else {
                self.hud.show(term: "", subtitle: "Couldn't read the selection", onUndo: {})
                return
            }
            let def = DefinitionService.define(captured.term)
            do {
                let entry = try self.store.saveLookup(
                    term: captured.term, definition: def.definition,
                    partOfSpeech: def.partOfSpeech, ipa: def.ipa, context: captured.context,
                    sourceApp: captured.sourceApp, sourceDetail: captured.sourceDetail, now: Date())
                self.appState.refresh()
                self.hud.show(term: entry.term, subtitle: "Card created · first review tomorrow") { [weak self] in
                    try? self?.store.deleteEntry(id: entry.id)
                    self?.appState.refresh()
                }
            } catch {
                self.hud.show(term: captured.term, subtitle: "Couldn't save", onUndo: {})
            }
        }
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build fails referencing `AppState` (not yet created) — that is expected; `AppState` arrives in Task 10. If you are executing strictly in order, proceed to Task 10 before running; otherwise temporarily comment out the `appState` usages to confirm the rest compiles, then restore.

- [ ] **Step 5: Commit**

```bash
git add Sources/VocabLook/UI/CaptureHUD.swift Sources/VocabLook/UI/HUDController.swift Sources/VocabLook/Capture/CaptureCoordinator.swift
git commit -m "feat: add capture HUD and capture coordinator"
```

---

## Task 10: AppState and the menu bar popover

**Files:**
- Create: `Sources/VocabLook/Services/AppState.swift`
- Create: `Sources/VocabLook/UI/MenuBarContentView.swift`
- Modify: `Sources/VocabLook/VocabLookApp.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Services/AppState.swift`**

```swift
import Foundation
import Combine

/// App-wide observable state for the popover and review flow.
@MainActor
final class AppState: ObservableObject {
    @Published var dueCount = 0
    @Published var capturedToday = 0
    @Published var totalLearned = 0
    @Published var recallPercent: Int? = nil
    @Published var streak = 0
    @Published var recents: [Entry] = []

    private let store: Store

    init(store: Store = .shared) {
        self.store = store
        streak = Settings.streakCount
        refresh()
    }

    func refresh() {
        let now = Date()
        dueCount = (try? store.dueCount(now: now)) ?? 0
        capturedToday = (try? store.capturedToday(now: now)) ?? 0
        totalLearned = (try? store.totalEntries()) ?? 0
        recallPercent = try? store.recallPercent()
        recents = (try? store.recentEntries()) ?? []
        streak = Settings.streakCount
    }

    /// Update the streak when a review session completes. One bump per local day.
    func registerReviewCompleted(now: Date = Date(), calendar: Calendar = .current) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: now)
        let yesterday = fmt.string(from: calendar.date(byAdding: .day, value: -1, to: now)!)

        switch Settings.lastReviewDay {
        case today: break
        case yesterday: Settings.streakCount += 1; Settings.lastReviewDay = today
        default: Settings.streakCount = 1; Settings.lastReviewDay = today
        }
        streak = Settings.streakCount
        refresh()
    }
}
```

- [ ] **Step 2: Create `Sources/VocabLook/UI/MenuBarContentView.swift`**

```swift
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dueCard
            statsRow
            Divider()
            recentList
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { app.refresh() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "book.closed.fill").foregroundStyle(.tint)
            Text("VocabLook").font(.system(size: 14, weight: .semibold))
            Spacer()
            if app.streak > 0 {
                Text("🔥 \(app.streak)").font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
            Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundColor(.secondary)
        }
    }

    private var dueCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.dueCount)").font(.system(size: 26, weight: .bold))
                Text("words due today").font(.system(size: 11.5)).opacity(0.85)
            }
            Spacer()
            Button("Start review →") {
                openWindow(id: "review")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.dueCount == 0)
        }
        .padding(14)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 11))
        .foregroundColor(.white)
    }

    private var statsRow: some View {
        HStack {
            stat("\(app.capturedToday)", "new today")
            Spacer()
            stat("\(app.totalLearned)", "learned")
            Spacer()
            stat(app.recallPercent.map { "\($0)%" } ?? "—", "recall")
        }
        .font(.system(size: 11.5)).foregroundColor(.secondary)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).foregroundColor(.primary).fontWeight(.semibold)
            Text(label)
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if app.recents.isEmpty {
                Text("No words yet today. Press ⌃⌘D on any word to capture it.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(app.recents) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.term).font(.system(size: 14, weight: .medium, design: .serif))
                        Text(entry.sourceApp ?? "").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Text(Self.timeFmt.string(from: entry.createdAt))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("History") { openWindow(id: "review") }.buttonStyle(.bordered).disabled(true)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.bordered)
        }
        .controlSize(.small)
    }
}
```

- [ ] **Step 3: Replace `Sources/VocabLook/VocabLookApp.swift`**

```swift
import SwiftUI

@main
struct VocabLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("VocabLook", systemImage: "book.closed") {
            MenuBarContentView().environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Review", id: "review") {
            ReviewView().environmentObject(appState)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView().environmentObject(appState)
        }
        .windowResizability(.contentSize)

        Window("Welcome to VocabLook", id: "onboarding") {
            OnboardingView().environmentObject(appState)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 4: Wire the coordinator in `AppDelegate.swift` (replace file)**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = CaptureCoordinator(appState: appState)
        coordinator.start()
        self.coordinator = coordinator
    }
}
```

Note: the popover and windows use the `@StateObject` `appState` from `VocabLookApp`; the coordinator uses its own `AppDelegate.appState`. To keep a single shared instance, change `VocabLookApp` to read the delegate's instance instead:

Replace in `VocabLookApp.swift` the line `@StateObject private var appState = AppState()` with:

```swift
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var appState: AppState { appDelegate.appState }
```

and remove the now-duplicate `@NSApplicationDelegateAdaptor` line at the top so there is exactly one. Because `appState` is now a plain computed property returning the delegate's `ObservableObject`, pass it via `.environmentObject(appState)` as already written. (AppState is `@MainActor`; the delegate is created on the main thread, so this is safe.)

- [ ] **Step 5: Build**

Run: `swift build`
Expected: Build complete (Task 9's `CaptureCoordinator` now resolves `AppState`). `ReviewView`, `SettingsView`, `OnboardingView` are referenced but created in later tasks — if building strictly in order, temporarily stub them as `struct ReviewView: View { var body: some View { Text("Review") } }` etc., then replace in their tasks. Create the three stubs now in their target files so the project builds.

- [ ] **Step 6: Create temporary stubs so the app builds and runs**

Create `Sources/VocabLook/UI/ReviewView.swift`, `SettingsView.swift`, `OnboardingView.swift`, each with a minimal body (replaced in later tasks):

```swift
import SwiftUI
struct ReviewView: View { var body: some View { Text("Review").frame(width: 460, height: 520) } }
```
```swift
import SwiftUI
struct SettingsView: View { var body: some View { Text("Settings").frame(width: 460, height: 360) } }
```
```swift
import SwiftUI
struct OnboardingView: View { var body: some View { Text("Onboarding").frame(width: 440, height: 420) } }
```

- [ ] **Step 7: Run and verify the popover + live capture**

Run: `./scripts/run.sh`
Grant Accessibility when prompted (System Settings → Privacy & Security → Accessibility → enable VocabLook), then relaunch with `./scripts/run.sh`.
Test: select a word in Safari/Notes, press `Ctrl+Cmd+D`. Expected: the native Look Up popover opens AND a "Saved <word>" HUD appears. Open the menu bar popover: due count / new-today / recent list reflect the capture.

- [ ] **Step 8: Commit**

```bash
git add Sources/VocabLook
git commit -m "feat: add AppState, menu bar popover, window scenes and capture wiring"
```

---

## Task 11: Review session and flashcard view

**Files:**
- Create: `Sources/VocabLook/Services/ReviewSession.swift`
- Replace: `Sources/VocabLook/UI/ReviewView.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Services/ReviewSession.swift`**

```swift
import Foundation

/// Drives a single review pass over the cards due now.
@MainActor
final class ReviewSession: ObservableObject {
    struct Item: Identifiable { let card: Card; let entry: Entry; var id: String { card.id } }

    @Published var queue: [Item] = []
    @Published var index = 0
    @Published var revealed = false

    private let store: Store
    private let total: Int

    var current: Item? { index < queue.count ? queue[index] : nil }
    var isFinished: Bool { index >= queue.count }
    var progressText: String { "\(min(index + 1, max(total, 1))) / \(max(total, 1))" }
    var progressFraction: Double { total == 0 ? 0 : Double(index) / Double(total) }

    init(store: Store = .shared, now: Date = Date()) {
        self.store = store
        let due = (try? store.dueCards(now: now)) ?? []
        self.queue = due.map { Item(card: $0.card, entry: $0.entry) }
        self.total = queue.count
    }

    func reveal() { revealed = true }

    func intervalPreview(_ grade: Grade, now: Date = Date()) -> String {
        guard let item = current else { return "" }
        return SRSEngine.preview(item.card, grade: grade, now: now)
    }

    /// Grade the current card, persist, and advance. Re-queues `.again` cards at the end.
    func grade(_ grade: Grade, now: Date = Date()) {
        guard let item = current else { return }
        let updated = SRSEngine.schedule(item.card, grade: grade, now: now)
        try? store.updateCard(updated)
        try? store.appendLog(ReviewLog(id: UUID().uuidString, cardId: item.card.id,
                                       grade: grade.rawValue, reviewedAt: now,
                                       prevInterval: item.card.intervalDays,
                                       newInterval: updated.intervalDays))
        if grade == .again {
            queue.append(Item(card: updated, entry: item.entry)) // relearn before finishing
        }
        index += 1
        revealed = false
    }
}
```

- [ ] **Step 2: Replace `Sources/VocabLook/UI/ReviewView.swift`**

```swift
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var session = ReviewSession()
    @Environment(\.dismiss) private var dismiss
    private let pronouncer = Pronouncer()

    var body: some View {
        Group {
            if session.isFinished {
                finished
            } else if let item = session.current {
                card(item)
            }
        }
        .frame(width: 460)
        .frame(minHeight: 520)
        .background(KeyCatcher { handleKey($0) })
    }

    // MARK: - Card

    private func card(_ item: ReviewSession.Item) -> some View {
        VStack(spacing: 0) {
            progressBar
            VStack(spacing: 6) {
                if let src = item.entry.sourceApp {
                    Label(src, systemImage: "globe")
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .padding(.bottom, 14)
                }
                Text(item.entry.term)
                    .font(.system(size: session.revealed ? 34 : 46, weight: .semibold, design: .serif))
                if let ipa = item.entry.ipa {
                    HStack(spacing: 12) {
                        Text(ipa).font(.system(size: 15, design: .monospaced)).foregroundColor(.secondary)
                        Button { pronouncer.speak(item.entry.term) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }.buttonStyle(.bordered).clipShape(Circle())
                    }.padding(.top, 8)
                }
                if let pos = item.entry.partOfSpeech {
                    Text(pos).font(.system(size: 14, design: .serif)).italic().foregroundColor(.secondary)
                }
            }
            .padding(.top, 14)

            if session.revealed {
                revealedContent(item)
            } else {
                Text("Press Space to reveal")
                    .font(.system(size: 12)).foregroundColor(.secondary).padding(.top, 26)
                Spacer()
            }
        }
        .padding(.horizontal, 26).padding(.bottom, 24)
    }

    private func revealedContent(_ item: ReviewSession.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 22)
            if let def = item.entry.definition {
                Text(def).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 14)
            } else {
                Text("No dictionary definition was found — recall the meaning from memory.")
                    .font(.system(size: 14)).foregroundColor(.secondary).padding(.bottom, 14)
            }
            if let ctx = item.entry.contextText {
                contextBlock(ctx, term: item.entry.term, source: item.entry.sourceApp)
            }
            grades
            Spacer(minLength: 0)
        }
        .onAppear { if Settings.pronounceOnReveal { pronouncer.speak(item.entry.term) } }
    }

    private func contextBlock(_ ctx: String, term: String, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(highlight(ctx, term: term))
                .font(.system(size: 14.5, design: .serif))
            if let source { Text("— from \(source)").font(.system(size: 11)).foregroundColor(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(Rectangle().fill(Color.accentColor).frame(width: 3), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 20)
    }

    private func highlight(_ text: String, term: String) -> AttributedString {
        var attr = AttributedString(text)
        if let range = attr.range(of: term, options: .caseInsensitive) {
            attr[range].foregroundColor = .accentColor
            attr[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return attr
    }

    private var grades: some View {
        HStack(spacing: 8) {
            gradeButton(.again, .red)
            gradeButton(.hard, .orange)
            gradeButton(.good, .green)
            gradeButton(.easy, .accentColor)
        }
    }

    private func gradeButton(_ grade: Grade, _ color: Color) -> some View {
        Button { apply(grade) } label: {
            VStack(spacing: 2) {
                Text(grade.label).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                Text(session.intervalPreview(grade)).font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        HStack(spacing: 12) {
            ProgressView(value: session.progressFraction)
            Text(session.progressText).font(.system(size: 12)).foregroundColor(.secondary)
                .monospacedDigit()
        }.padding(.vertical, 16)
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.tint)
            Text("All done for today").font(.system(size: 19, weight: .semibold))
            Text("🔥 \(app.streak)-day streak").foregroundColor(.secondary)
            Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .onAppear { app.registerReviewCompleted() }
    }

    // MARK: - Keyboard

    private func handleKey(_ key: String) {
        if !session.revealed {
            if key == " " { session.reveal() }
            return
        }
        switch key {
        case "1": apply(.again)
        case "2": apply(.hard)
        case "3": apply(.good)
        case "4": apply(.easy)
        default: break
        }
    }

    private func apply(_ grade: Grade) {
        session.grade(grade)
        app.refresh()
    }
}

/// Bridges hardware keyDown to a closure for the review window.
struct KeyCatcher: NSViewRepresentable {
    let onKey: (String) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = KeyView(); v.onKey = onKey; return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onKey: ((String) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
        override func keyDown(with event: NSEvent) {
            onKey?(event.charactersIgnoringModifiers ?? "")
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: fails referencing `Pronouncer` (Task 12). Create the Pronouncer in Task 12 first, or temporarily stub `struct Pronouncer { func speak(_ s: String) {} }`. Then build to completion.

- [ ] **Step 4: Manual verify**

Run: `./scripts/run.sh`. Open the popover → Start review. Expected: a card shows the word/IPA; Space reveals definition + highlighted context sentence + 4 grade buttons with interval previews; clicking/keys 1–4 advance; finishing shows "All done" and the streak increments.

- [ ] **Step 5: Commit**

```bash
git add Sources/VocabLook/Services/ReviewSession.swift Sources/VocabLook/UI/ReviewView.swift
git commit -m "feat: add review session and flashcard view with SM-2 grading"
```

---

## Task 12: Pronouncer (text-to-speech)

**Files:**
- Create: `Sources/VocabLook/Services/Pronouncer.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Services/Pronouncer.swift`**

```swift
import AVFoundation

/// Speaks a word using the system speech synthesizer.
final class Pronouncer {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }
}
```

If a temporary `Pronouncer` stub was added in Task 11, delete it first.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Manual verify**

Run: `./scripts/run.sh`, open a review card, click the speaker button. Expected: the word is spoken aloud.

- [ ] **Step 4: Commit**

```bash
git add Sources/VocabLook/Services/Pronouncer.swift
git commit -m "feat: add text-to-speech pronouncer"
```

---

## Task 13: Daily reminder notification

**Files:**
- Create: `Sources/VocabLook/Services/Reminder.swift`
- Modify: `Sources/VocabLook/AppDelegate.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Services/Reminder.swift`**

```swift
import Foundation
import UserNotifications

/// Schedules one repeating daily local notification at the user's chosen time.
final class Reminder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminder()
    private let center = UNUserNotificationCenter.current()
    private let identifier = "vocablook.daily"

    func configure() {
        center.delegate = self
        Permissions.requestNotifications { [weak self] granted in
            if granted { self?.reschedule() }
        }
    }

    /// Re-create the daily trigger from current settings + due count.
    func reschedule() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let due = (try? Store.shared.dueCount(now: Date())) ?? 0
        let content = UNMutableNotificationContent()
        content.title = "VocabLook"
        content.body = due > 0
            ? "\(due) words ready to review — keep your 🔥 \(Settings.streakCount)-day streak."
            : "Time for today's vocabulary review."
        content.sound = .default

        var date = DateComponents()
        date.hour = Settings.reminderHour
        date.minute = Settings.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Show the banner even when (rarely) our app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Tapping the notification opens the review window.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSWorkspaceOpenReview()
        }
        completionHandler()
    }
}

import AppKit
/// Opens the Review window from a non-SwiftUI context by activating the app and posting a custom action.
func NSWorkspaceOpenReview() {
    NSApp.activate(ignoringOtherApps: true)
    NotificationCenter.default.post(name: .openReviewWindow, object: nil)
}

extension Notification.Name {
    static let openReviewWindow = Notification.Name("vocablook.openReview")
}
```

- [ ] **Step 2: Open the review window when the notification fires — modify `VocabLookApp.swift`**

Add an `.onReceive` to the `MenuBarExtra` content (or any always-present scene view). Replace the `MenuBarExtra` block in `VocabLookApp.swift` with:

```swift
        MenuBarExtra("VocabLook", systemImage: "book.closed") {
            MenuBarContentView()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: .openReviewWindow)) { _ in
                    openWindowFromMenu("review")
                }
        }
        .menuBarExtraStyle(.window)
```

And add at the top of `VocabLookApp` struct body the environment accessor and helper:

```swift
    @Environment(\.openWindow) private var openWindowEnv
    private func openWindowFromMenu(_ id: String) { openWindowEnv(id: id) }
```

(If `@Environment(\.openWindow)` is unavailable at `App` scope in your SDK, instead handle `.openReviewWindow` inside `MenuBarContentView` using its own `@Environment(\.openWindow)` and call `openWindow(id: "review")`.)

- [ ] **Step 3: Configure the reminder in `AppDelegate.swift` (replace file)**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = CaptureCoordinator(appState: appState)
        coordinator.start()
        self.coordinator = coordinator

        Reminder.shared.configure()

        if !Settings.didOnboard || !Permissions.isAccessibilityTrusted() {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openOnboarding, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let openOnboarding = Notification.Name("vocablook.openOnboarding")
}
```

Also add the matching `.onReceive(...for: .openOnboarding)` next to the review one in `VocabLookApp.swift`, calling `openWindowFromMenu("onboarding")`.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Manual verify**

Set the reminder time to ~2 minutes ahead (temporarily, via `Settings.reminderHour/Minute` in code or after Task 14's UI), run `./scripts/run.sh`, grant Notifications. Expected: at the set time a VocabLook notification appears; clicking it opens the Review window.

- [ ] **Step 6: Commit**

```bash
git add Sources/VocabLook/Services/Reminder.swift Sources/VocabLook/AppDelegate.swift Sources/VocabLook/VocabLookApp.swift
git commit -m "feat: add daily reminder notification opening the review window"
```

---

## Task 14: Onboarding, Settings, and launch-at-login

**Files:**
- Create: `Sources/VocabLook/Services/LaunchAtLogin.swift`
- Replace: `Sources/VocabLook/UI/OnboardingView.swift`
- Replace: `Sources/VocabLook/UI/SettingsView.swift`

- [ ] **Step 1: Create `Sources/VocabLook/Services/LaunchAtLogin.swift`**

```swift
import ServiceManagement

/// Toggle the app as a login item via the modern SMAppService API (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: Replace `Sources/VocabLook/UI/OnboardingView.swift`**

```swift
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var trusted = Permissions.isAccessibilityTrusted()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill").font(.system(size: 34)).foregroundStyle(.tint)
            Text("One quick permission").font(.system(size: 19, weight: .semibold))
            Text("To read the word you look up, VocabLook needs macOS Accessibility access. It only reads the selection when you press ⌃⌘D.")
                .font(.system(size: 13.5)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open System Settings → Privacy & Security → Accessibility")
                step(2, "Turn on VocabLook")
                step(3, "Look up a word to test it")
            }
            .padding(.vertical, 4)

            HStack {
                Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
                Button(trusted ? "Done ✓" : "I've enabled it") {
                    trusted = Permissions.isAccessibilityTrusted()
                    Settings.didOnboard = true
                    if trusted { dismiss() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(width: 440)
        .onAppear { _ = Permissions.promptAccessibility() }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 11) {
            Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .frame(width: 22, height: 22).background(Color.accentColor, in: Circle())
            Text(text).font(.system(size: 13))
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    }
}
```

- [ ] **Step 3: Replace `Sources/VocabLook/UI/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @State private var reminder = Calendar.current.date(
        from: DateComponents(hour: Settings.reminderHour, minute: Settings.reminderMinute)) ?? Date()
    @State private var dailyGoal = Double(Settings.dailyGoal)
    @State private var pronounce = Settings.pronounceOnReveal
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            LabeledContent("Capture shortcut") {
                Text("⌃⌘D").font(.system(.body, design: .monospaced))
                    .help("Mirrors the macOS Look Up shortcut — observe only")
            }
            DatePicker("Daily reminder", selection: $reminder, displayedComponents: .hourAndMinute)
                .onChange(of: reminder) { _, newValue in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    Settings.reminderHour = c.hour ?? 20
                    Settings.reminderMinute = c.minute ?? 30
                    Reminder.shared.reschedule()
                }
            VStack(alignment: .leading) {
                Text("New cards per day: \(Int(dailyGoal))")
                Slider(value: $dailyGoal, in: 5...100, step: 5)
                    .onChange(of: dailyGoal) { _, v in Settings.dailyGoal = Int(v) }
            }
            Toggle("Pronounce on reveal", isOn: $pronounce)
                .onChange(of: pronounce) { _, v in Settings.pronounceOnReveal = v }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.set(v) }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Manual verify**

Run: `./scripts/run.sh`. Open Settings from the popover gear: change reminder time, daily goal slider, toggles. Confirm values persist after relaunch (reopen Settings — they reflect saved state). Toggle Launch at login and confirm VocabLook appears in System Settings → General → Login Items.

- [ ] **Step 6: Commit**

```bash
git add Sources/VocabLook/Services/LaunchAtLogin.swift Sources/VocabLook/UI/OnboardingView.swift Sources/VocabLook/UI/SettingsView.swift
git commit -m "feat: add onboarding, settings and launch-at-login"
```

---

## Task 15: Full integration pass and release build

**Files:**
- Modify (only if issues found): any of the above.
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

```markdown
# VocabLook

A macOS menu bar app that captures the words you look up with the native **Ctrl+Cmd+D**
and turns them into SM-2 spaced-repetition flashcards. 100% local, fully offline.

## Run (development)
```bash
./scripts/run.sh           # build (debug) + bundle + launch VocabLook.app
```
Grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility),
then relaunch. Grant **Notifications** for the daily reminder.

## Build a release
```bash
./scripts/run.sh release
```

## How it works
- `Ctrl+Cmd+D` is observed (not consumed) — the native Look Up still opens.
- The selected word + surrounding sentence + source app are captured via the Accessibility API.
- Definition/IPA come from macOS Dictionary Services.
- Cards are scheduled with SM-2; a daily notification opens the review window.
```

- [ ] **Step 2: Release build + bundle**

Run: `./scripts/run.sh release`
Expected: builds in release mode, bundles, launches.

- [ ] **Step 3: Full manual acceptance checklist**

Verify end-to-end:
- [ ] First launch shows onboarding; granting Accessibility lets capture work.
- [ ] `Ctrl+Cmd+D` on a word in Safari, Books, Notes, and Mail → native Look Up opens AND a "Saved" HUD appears.
- [ ] Undo on the HUD removes the just-saved word (popover counts drop).
- [ ] Looking up the same word twice does not create a duplicate.
- [ ] A word with no selection / unreadable selection shows "Couldn't read the selection" and saves nothing.
- [ ] Popover shows due count, new-today, total, recall %, recent list, streak.
- [ ] Review: Space reveals; definition + highlighted context show; grade buttons show interval previews; keys 1–4 work.
- [ ] `Again` re-queues the card later in the same session; finishing increments the streak.
- [ ] Daily notification fires at the set time and opens review on click.
- [ ] Settings persist across relaunch; Launch at login registers.

- [ ] **Step 4: Self-review the spec coverage**

Confirm each spec section maps to behavior: capture (Tasks 7–9), definitions (5), storage/dedup (3), SM-2 (4), screens (10–14), notification/streak (13/10), error handling (8/9/11), privacy (no network anywhere). Fix any gap found.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add README and complete integration pass"
```

---

## Notes & known dev-time caveats

- **Re-granting Accessibility:** ad-hoc signing changes the binary hash each build, so macOS may ask to re-grant Accessibility after a rebuild. For a stable identity, create a self-signed code-signing certificate and sign with it in `bundle-app.sh` (deferred; not required for MVP).
- **Context sentence** is best-effort: apps that don't expose `AXValue`/`AXSelectedTextRange` (some web/Electron views) will have `context == nil`; the card still works.
- **`menuBarExtraStyle(.window)`** is required for the rich popover layout (vs the default menu style).
- **Daily-goal capping** of *new* cards is stored in Settings and surfaced in the UI; due reviews are never capped (per spec §6). If you later introduce more new cards than the goal in a day, enforce the cap when building the review queue in `ReviewSession.init`.
