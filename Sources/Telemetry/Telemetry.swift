import Foundation

struct Telemetry {

    // BOREAL_DIALER_v829_RELIABILITY - release builds now keep these too (DialerEventLog sends them to BF-Server).
    static func event(_ name: String, metadata: [String: String] = [:], callRef: String? = nil) {
#if DEBUG
        print("EVENT:", name, metadata)
#endif
        DialerEventLog.shared.record(name, metadata: metadata, callRef: callRef)
    }
}
