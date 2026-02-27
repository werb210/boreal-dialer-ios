import Foundation

protocol VoiceServiceProtocol {
    func startCall(to number: String)
    func endCall()
}

final class VoiceService: VoiceServiceProtocol {

    static let shared = VoiceService()

    private let tokenProvider: TokenProvider
    private let callState = CallState()
    private var activeUUID: UUID?

    init(tokenProvider: TokenProvider = MockTokenProvider()) {
        self.tokenProvider = tokenProvider
    }

    func startCall(to number: String) {
        callState.status = .connecting
        callState.activeNumber = number

        activeUUID = UUID()

        CallKitManager.shared.startCall(to: number)

        Task {
            do {
                let token = try await tokenProvider.fetchAccessToken()
                print("Fetched token: \(token)")
                simulateCallConnection()
            } catch {
                callState.status = .failed("Token fetch failed")
            }
        }
    }

    func endCall() {
        if let uuid = activeUUID {
            CallKitManager.shared.endCall(uuid: uuid)
        }

        callState.status = .ended
        callState.activeNumber = nil
    }

    private func simulateCallConnection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.callState.status = .active
        }
    }

    func getCallState() -> CallState {
        return callState
    }
}
