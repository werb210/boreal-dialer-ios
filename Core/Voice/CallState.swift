import Foundation
import Combine

enum CallStatus {
    case idle
    case connecting
    case ringing
    case active
    case ended
    case failed(String)
}

final class CallState: ObservableObject {
    @Published var status: CallStatus = .idle
    @Published var activeNumber: String?
}
