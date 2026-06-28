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
