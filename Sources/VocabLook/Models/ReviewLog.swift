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
