import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct CallActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var startedAt: Date
    }
    var handle: String
    var line: String
}
