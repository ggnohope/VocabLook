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
