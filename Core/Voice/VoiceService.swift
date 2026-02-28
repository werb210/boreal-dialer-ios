import Foundation
import TwilioVoice
import CallKit

protocol VoiceServiceProtocol {
    func startCall(to number: String)
    func endCall()
}

final class VoiceService: NSObject, ObservableObject, VoiceServiceProtocol {

    static let shared = VoiceService()

    private let tokenProvider: TokenProvider
    private let durationManager = CallDurationManager.shared
    private let callState = CallState()
    private var callStartDate: Date?
    private var currentDirection: CallDirection = .outbound

    private var callKitProvider: CXProvider!
    private var callKitController = CXCallController()

    private(set) var activeCall: Call?

    init(tokenProvider: TokenProvider = BFTokenProvider()) {
        self.tokenProvider = tokenProvider
        super.init()

        let config = CXProviderConfiguration(localizedName: "Boreal")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber]

        callKitProvider = CXProvider(configuration: config)
        callKitProvider.setDelegate(self, queue: nil)
    }

    // MARK: - Outgoing

    func startCall(to number: String) {

        currentDirection = .outbound
        callStartDate = Date()

        callState.status = .connecting
        callState.activeNumber = number

        Task {
            do {
                let activeLine = LineManager.shared.activeLine

                guard let line = activeLine else {
                    callState.status = .failed("No active line")
                    return
                }

                let token = try await tokenProvider.fetchAccessToken(
                    forLine: line.id
                )

                let options = ConnectOptions(accessToken: token) { builder in
                    builder.params = ["To": number]
                }

                activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
                CallKitManager.shared.startCall(to: number)

            } catch {
                callState.status = .failed("Token fetch failed")
            }
        }
    }

    // MARK: - Incoming

    func handleIncomingCall(_ call: Call) {
        currentDirection = .inbound
        callStartDate = Date()

        activeCall = call
        activeCall?.delegate = self

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber,
                                       value: call.from ?? "Unknown")
        update.hasVideo = false

        callKitProvider.reportNewIncomingCall(
            with: UUID(),
            update: update
        ) { error in
            if let error = error {
                print("CallKit report error:", error)
            }
        }
    }

    func endCall() {
        activeCall?.disconnect()
        callState.status = .ended
        callState.activeNumber = nil
    }

    func answerIncomingCall() {
        activeCall?.accept()
        callState.status = .active
    }

    func rejectIncomingCall() {
        activeCall?.reject()
        callState.status = .ended
    }

    func reset() {
        activeCall?.disconnect()
        activeCall = nil
        callState.status = .idle
        callState.activeNumber = nil
    }

    func getCallState() -> CallState {
        callState
    }
}

extension VoiceService: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        activeCall?.disconnect()
        activeCall = nil
        durationManager.stop()
        callState.status = .idle
    }
}

extension VoiceService: CallDelegate {

    func callDidStartRinging(_ call: Call) {
        print("Call ringing")
    }

    func callDidConnect(_ call: Call) {
        callState.status = .active
        durationManager.start()
    }

    func callDidDisconnect(_ call: Call, error: Error?) {

        let end = Date()
        let start = callStartDate ?? end
        let duration = Int(end.timeIntervalSince(start))

        let result: CallResult = {
            if error != nil { return .failed }
            if duration == 0 && currentDirection == .inbound {
                return .missed
            }
            return .completed
        }()

        let log = CallLog(
            id: UUID(),
            phoneNumber: call.from ?? call.to ?? "Unknown",
            direction: currentDirection,
            result: result,
            startedAt: start,
            endedAt: end,
            durationSeconds: duration
        )

        CallLogStore.shared.add(log)

        durationManager.stop()
        callState.status = .ended
        activeCall = nil
    }

    func callDidFailToConnect(_ call: Call, error: Error) {

        let now = Date()

        let log = CallLog(
            id: UUID(),
            phoneNumber: call.from ?? call.to ?? "Unknown",
            direction: currentDirection,
            result: .failed,
            startedAt: callStartDate ?? now,
            endedAt: now,
            durationSeconds: 0
        )

        CallLogStore.shared.add(log)

        durationManager.stop()
        callState.status = .failed(error.localizedDescription)
        activeCall = nil
    }
}

extension VoiceService: NotificationDelegate {

    func callInviteReceived(_ callInvite: CallInvite) {
        let call = callInvite.accept(with: self)
        handleIncomingCall(call)
    }
}
