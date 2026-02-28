import Foundation

enum CallDirection: String, Codable {
    case inbound
    case outbound
}

enum CallResult: String, Codable {
    case completed
    case missed
    case failed
    case rejected
}

struct CallLog: Identifiable, Codable {
    let id: UUID
    let phoneNumber: String
    let direction: CallDirection
    let result: CallResult
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
}
