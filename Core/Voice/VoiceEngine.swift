import Foundation
import CallKit
import TwilioVoice

@MainActor
final class VoiceEngine: NSObject, ObservableObject {

    static let shared = VoiceEngine()

    enum State: CustomStringConvertible {
        case idle
        case ringing(UUID)
        case dialing(UUID)
        case active(UUID)
        case ended
        case failed

        var description: String {
            switch self {
            case .idle:
                return "idle"
            case .ringing(let uuid):
                return "ringing(\(uuid.uuidString))"
            case .dialing(let uuid):
                return "dialing(\(uuid.uuidString))"
            case .active(let uuid):
                return "active(\(uuid.uuidString))"
            case .ended:
                return "ended"
            case .failed:
                return "failed"
            }
        }
    }

    enum Line: String {
        case bf
        case bi
        case slf

        var backendLineId: String {
            rawValue.uppercased()
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var callDuration: Int = 0
    @Published var activeLine: Line = .bf
    @Published var silo: Silo = .bf

    private var provider: CXProvider!
    private var timer: Timer?

    private override init() {
        super.init()
        configureCallKit()
    }

    private func configureCallKit() {
        let config = CXProviderConfiguration(localizedName: "Boreal")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber]

        provider = CXProvider(configuration: config)
        provider.setDelegate(self, queue: nil)
    }

    func startCall(to number: String) {
        guard case .idle = state else { return }

        let uuid = UUID()
        state = .dialing(uuid)

        let handle = CXHandle(type: .phoneNumber, value: number)
        let start = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: start)

        CXCallController().request(transaction) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.handleFailure()
            }
        }

        Telemetry.event("call_start", metadata: ["number": number, "silo": silo.rawValue])
        TwilioVoiceManager.shared.startCall(uuid: uuid, to: number)
    }

    func reportIncoming(uuid: UUID, handle: String) {
        guard case .idle = state else { return }

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            guard let self else { return }
            if error == nil {
                self.state = .ringing(uuid)
            }
        }
    }

    func setActiveLine(_ line: Line) {
        activeLine = line
        silo = Silo(rawValue: line.rawValue) ?? .bf
    }

    func forceTerminate() {
        TwilioVoiceManager.shared.disconnect()
        finishCall(status: .ended)
    }

    func syncWithServer(_ serverCalls: [RemoteCallStatus]) {
        if serverCalls.isEmpty {
            forceTerminate()
            return
        }

        guard case .idle = state else { return }

        if let ringing = serverCalls.first(where: { $0.status == "ringing" }),
           let uuid = UUID(uuidString: ringing.id) {
            reportIncoming(uuid: uuid, handle: ringing.number)
        }
    }

    func reconcile() async {
        let serverCalls = try? await API.getActiveCalls()

        if serverCalls?.isEmpty == true {
            state = .idle
        }
    }

    func handleIncomingEvent(_ payload: DataContainer) {
        guard
            let id = payload.id,
            let uuid = UUID(uuidString: id),
            let number = payload.number
        else {
            return
        }

        reportIncoming(uuid: uuid, handle: number)
    }

    func handleCallConnected(uuid: UUID) {
        stopTimer()
        startTimer()
        state = .active(uuid)
    }

    func handleFailure() {
        finishCall(status: .failed)
    }

    func handleDisconnect() {
        Telemetry.event("call_end", metadata: ["duration": "\(callDuration)"])
        finishCall(status: .ended)
    }

    private func finishCall(status: State) {
        stopTimer()
        state = status

        Task {
            try? await API.logCall(duration: callDuration, status: "\(status)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.state = .idle
        }
    }

    private func startTimer() {
        callDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.callDuration += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension VoiceEngine: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        TwilioVoiceManager.shared.disconnect()
        stopTimer()
        state = .idle
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        TwilioVoiceManager.shared.accept()
        startTimer()
        state = .active(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        TwilioVoiceManager.shared.disconnect()
        finishCall(status: .ended)
        action.fulfill()
    }
}
