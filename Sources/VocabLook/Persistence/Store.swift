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
            let entry = Entry(id: UUID().uuidString, term: term, normalized: normalized,
                              definition: definition, partOfSpeech: partOfSpeech, ipa: ipa,
                              contextText: context, sourceApp: sourceApp, sourceDetail: sourceDetail,
                              createdAt: now)
            try entry.insert(db)
            let card = Card.fresh(entryId: entry.id, now: now)
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

    /// Every card paired with its entry, oldest-due first. Used by "Review all" (practice ahead).
    func allCards() throws -> [(card: Card, entry: Entry)] {
        try dbQueue.read { db in
            let cards = try Card.order(Column("dueAt").asc).fetchAll(db)
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
        try dbQueue.write { db in try log.insert(db) }
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
