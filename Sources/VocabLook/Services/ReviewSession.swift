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
        let goal = max(0, Settings.dailyGoal)
        var newSeen = 0
        let selected = due.filter { pair in
            if pair.card.repetitions == 0 {
                guard newSeen < goal else { return false }
                newSeen += 1
                return true
            }
            return true
        }
        let items = selected.map { Item(card: $0.card, entry: $0.entry) }
        self.queue = items
        self.total = items.count
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
