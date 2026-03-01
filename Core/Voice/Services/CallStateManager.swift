import Foundation

enum CallState {
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

    func current() -> CallState {
        queue.sync { state }
    }

    func reset() {
        queue.sync {
            state = .idle
        }
    }
}
