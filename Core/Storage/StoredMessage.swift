import Foundation
import SwiftData

@Model
final class StoredMessage {

    var id: String
    var lineId: String
    var conversationId: String
    var body: String
    var author: String
    var timestamp: Date

    init(
        id: String,
        lineId: String,
        conversationId: String,
        body: String,
        author: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.lineId = lineId
        self.conversationId = conversationId
        self.body = body
        self.author = author
        self.timestamp = timestamp
    }
}
