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
