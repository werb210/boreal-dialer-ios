import Foundation

struct SocketEvent: Codable {
    let type: String
    let payload: DataContainer
}

struct DataContainer: Codable {
    let id: String?
    let number: String?
    let status: String?
    let body: String?
    let direction: String?
    let timestamp: Date?
}
