import Foundation

enum CallState: Equatable {
    case idle
    case ringing
    case connecting
    case connected
    case ended
}

final class CallStateManager {
    static let shared = CallStateManager()

    private(set) var state: CallState = .idle
    private let queue = DispatchQueue(label: "call.state.queue")

    private init() {}

    func transition(to newState: CallState) {
        queue.sync {
            state = newState
        }
    }

    @discardableResult
    func transition(from expectedState: CallState, to newState: CallState) -> Bool {
        queue.sync {
            guard state == expectedState else { return false }
            state = newState
            return true
        }
    }

    func current() -> CallState {
        queue.sync { state }
    }

    func reset() {
        queue.sync {
            state = .idle
        }
    }
}
