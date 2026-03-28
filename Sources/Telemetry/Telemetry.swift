import Foundation

struct Telemetry {

    static func event(_ name: String, metadata: [String: String] = [:]) {
#if DEBUG
        print("EVENT:", name, metadata)
#endif
    }
}
