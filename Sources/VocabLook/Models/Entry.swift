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
