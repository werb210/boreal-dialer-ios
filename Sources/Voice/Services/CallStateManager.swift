// BOREAL_DIALER_MODULE_COMPILES_v4 - was a second enum named CallState, which
// made every reference to the type ambiguous across the module.
import Foundation

enum CallPhase: Equatable {
    case idle
    case ringing
    case connecting
    case connected
    case ended
}

final class CallStateManager {
    static let shared = CallStateManager()

    private(set) var state: CallPhase = .idle
    private let queue = DispatchQueue(label: "call.state.queue")

    private init() {}

    func transition(to newState: CallPhase) {
        queue.sync {
            state = newState
        }
    }

    @discardableResult
    func transition(from expectedState: CallPhase, to newState: CallPhase) -> Bool {
        queue.sync {
            guard state == expectedState else { return false }
            state = newState
            return true
        }
    }

    func current() -> CallPhase {
        queue.sync { state }
    }

    func reset() {
        queue.sync {
            state = .idle
        }
    }
}
