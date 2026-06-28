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
