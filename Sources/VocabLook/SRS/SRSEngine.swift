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
