import Foundation
import SwiftData

@Model
final class PersistedCallLog {

    var id: UUID
    var lineId: String
    var phoneNumber: String
    var direction: String
    var status: String
    var timestamp: Date
    var duration: Int?

    init(
        id: UUID = UUID(),
        lineId: String,
        phoneNumber: String,
        direction: String,
        status: String,
        timestamp: Date = Date(),
        duration: Int? = nil
    ) {
        self.id = id
        self.lineId = lineId
        self.phoneNumber = phoneNumber
        self.direction = direction
        self.status = status
        self.timestamp = timestamp
        self.duration = duration
    }
}
