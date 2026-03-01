import Foundation
import Combine

@MainActor
final class CallManager: ObservableObject {

    static let shared = CallManager()

    @Published private(set) var state: CallState = .idle
    @Published private(set) var activeCallUUID: UUID?
    @Published private(set) var activeLine: Line = .bf
    @Published private(set) var callDuration: Int = 0

    private var timer: Timer?

    private init() {}

    func startCall(to number: String) {
        guard state == .idle else { return }
        guard activeLine == LineManager.shared.activeLine else { return }

        let uuid = UUID()
        activeCallUUID = uuid
        state = .dialing

        VoiceService.shared.startCall(uuid: uuid, to: number)
    }

    func incomingCall(uuid: UUID) {
        guard state == .idle else { return }
        activeCallUUID = uuid
        state = .ringing
    }

    @discardableResult
    func startIncomingCall(from number: String, uuid: UUID) -> Bool {
        _ = number
        guard activeLine == LineManager.shared.activeLine else { return false }
        guard state == .idle else { return false }

        incomingCall(uuid: uuid)
        return true
    }

    func answerCall(uuid: UUID) {
        guard activeCallUUID == uuid else { return }

        Task {
            try? await API.answerCall(uuid: uuid.uuidString)
        }
    }

    func callDidConnect() {
        guard state == .dialing || state == .ringing else { return }

        state = .active
        startTimer()
    }

    func callDidFail() {
        state = .failed
        writeCallLog(status: state.rawValue, duration: callDuration)
        cleanup()
    }

    func endCall() {
        guard let uuid = activeCallUUID else { return }

        VoiceService.shared.endCall(uuid: uuid)
        state = .ended
        writeCallLog(status: state.rawValue, duration: callDuration)
        cleanup()
    }

    func endCall(uuid: UUID) {
        guard activeCallUUID == uuid else { return }
        endCall()
    }

    func syncWithServer(_ serverCalls: [RemoteCallStatus]) {
        if serverCalls.isEmpty {
            forceTerminate()
            return
        }

        guard let uuid = activeCallUUID else {
            if let ringingCall = serverCalls.first(where: { $0.status == "ringing" }),
               let ringingUUID = UUID(uuidString: ringingCall.id),
               startIncomingCall(from: ringingCall.number, uuid: ringingUUID) {
                CallKitManager.shared.reportIncomingCall(uuid: ringingUUID, handle: ringingCall.number)
            }
            return
        }

        let serverUUIDs = Set(serverCalls.compactMap { UUID(uuidString: $0.id) })
        if !serverUUIDs.contains(uuid) {
            forceTerminate()
        }
    }

    func forceTerminate() {
        if let uuid = activeCallUUID {
            CallKitManager.shared.endCall(uuid: uuid)
        }

        state = .ended
        writeCallLog(status: state.rawValue, duration: callDuration)
        cleanup()
    }

    func setActiveLine(_ line: Line) {
        activeLine = line
    }

    private func cleanup() {
        stopTimer()
        activeCallUUID = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.state = .idle
        }
    }

    private func startTimer() {
        stopTimer()

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
        callDuration = 0
    }

    private func writeCallLog(status: String, duration: Int) {
        Task {
            try? await API.logCall(duration: duration, status: status)
        }
    }
}

private extension Line {
    static let bf = Line(
        id: "BF",
        name: "Boreal Financial",
        baseURL: URL(string: "https://bf-server.com")!,
        wsURL: nil
    )
}
