import Foundation

struct MessageModel: Identifiable {
    let id: String
    let body: String
    let author: String
    let timestamp: Date
}
