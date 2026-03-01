import Foundation

struct Telemetry {

    static func event(_ name: String, metadata: [String: String] = [:]) {
        print("EVENT:", name, metadata)
    }
}
