import Foundation

struct CallLog: Identifiable, Codable {
    let id: UUID
    let direction: String
    let timestamp: Date
    let duration: TimeInterval
}
