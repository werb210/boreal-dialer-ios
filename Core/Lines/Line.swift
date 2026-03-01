import Foundation

struct Line: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let baseURL: URL
    let wsURL: URL?
}
