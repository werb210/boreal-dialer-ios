import Foundation

struct CallLog: Identifiable, Codable {
    let id: UUID
    let callSid: String?
    let direction: String
    let timestamp: Date
    let duration: TimeInterval
}
