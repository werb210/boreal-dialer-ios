import Foundation
import TwilioVoice
import CallKit

protocol VoiceServiceProtocol {
    func startCall(to number: String)
    func endCall()
}

@MainActor
final class VoiceService: NSObject, ObservableObject, VoiceServiceProtocol {

    static let shared = VoiceService()

    private let tokenProvider: TokenProvider
    private var callStartDate: Date?
    private var currentDirection: CallDirection = .outbound
    private var pollingTask: Task<Void, Never>?

    private var callKitProvider: CXProvider!
    private var callKitController = CXCallController()

    private(set) var activeCall: Call?
    private(set) var activeNumber: String?
    private var callInvite: CallInvite?

    init(tokenProvider: TokenProvider = BFTokenProvider()) {
        // BOREAL_DIALER_SURVIVE_FIRST_RUN_v21 - identity arrives with the login
        // token. Before that this object simply cannot place calls, which the
        // call paths already guard.
        if IdentityManager.shared.identity == nil {
            print("[voice] VoiceService constructed before identity was configured")
        }

        self.tokenProvider = tokenProvider
        super.init()

        let config = CXProviderConfiguration(localizedName: "Boreal")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.includesCallsInRecents = true
        config.supportedHandleTypes = [.phoneNumber]

        callKitProvider = CXProvider(configuration: config)
        callKitProvider.setDelegate(self, queue: nil)
    }

    func handleIncoming(_ payload: DataContainer) {
        guard let number = payload.number else { return }

        activeNumber = number

        persistCall(
            CallModel(
                id: payload.id ?? UUID().uuidString,
                number: number,
                direction: payload.direction ?? "inbound",
                status: "ringing",
                startedAt: payload.timestamp ?? Date(),
                endedAt: nil
            ),
            line: LineManager.shared.activeLine
        )
    }

    func handleUpdate(_ payload: DataContainer) {
        guard let id = payload.id else { return }
        updateCallStatus(id: id, status: payload.status ?? "")
    }

    func startCall(to number: String) {
        CallManager.shared.startCall(to: number)
    }

    func startCall(uuid: UUID, to number: String) {
        currentDirection = .outbound
        callStartDate = Date()
        activeNumber = number

        let line = LineManager.shared.activeLine
        persistCall(
            CallModel(
                id: uuid.uuidString,
                number: number,
                direction: "outbound",
                status: "dialing",
                startedAt: callStartDate ?? Date(),
                endedAt: nil
            ),
            line: line
        )

        Task {
            do {
                let token = try await tokenProvider.fetchAccessToken(forLine: line.id)

                let options = ConnectOptions(accessToken: token) { builder in
                    builder.params = ["To": number]
                }

                activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
                CallKitManager.shared.startCall(uuid: uuid, to: number)

            } catch {
                await MainActor.run {
                    CallManager.shared.callDidFail()
                }
            }
        }
    }

    func handleIncomingCall(uuid: UUID, number: String) {
        currentDirection = .inbound
        callStartDate = Date()
        activeNumber = number

        persistCall(
            CallModel(
                id: uuid.uuidString,
                number: number,
                direction: "inbound",
                status: "ringing",
                startedAt: callStartDate ?? Date(),
                endedAt: nil
            ),
            line: LineManager.shared.activeLine
        )
    }

    func endCall() {
        activeCall?.disconnect()
        activeCall = nil
        callInvite = nil

        try? AVAudioSession.sharedInstance().setActive(false)
        CallManager.shared.endCall()
    }


    func acceptCallInvite() {
        guard CallStateManager.shared.current() == .connecting else {
            callInvite?.reject()
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .duckOthers]
        )
        try? session.setActive(true)

        activeCall = callInvite?.accept(with: self)
        callInvite = nil
    }
    func endCall(uuid: UUID) {
        guard CallManager.shared.activeCallUUID == uuid else { return }

        // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - hanging up is a client-side SDK
        // operation; Twilio's status callback is what tells the server.
        activeCall?.disconnect()
        activeNumber = nil
    }

    func acceptCall(uuid: UUID) {
        guard CallManager.shared.activeCallUUID == uuid else { return }

        // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - the delegate is passed to
        // accept(with:); Call exposes no delegate property to assign afterwards.
        if let invite = callInvite {
            activeCall = invite.accept(with: self)
            callInvite = nil
            return
        }

        CallStateManager.shared.reset()
    }

    func rejectCall(uuid: UUID) {
        guard CallManager.shared.activeCallUUID == uuid else { return }

        if let invite = callInvite {
            invite.reject()
            callInvite = nil
            activeNumber = nil
            return
        }

        // BOREAL_DIALER_SDK_AND_ISOLATION_v5
        activeCall?.disconnect()
        activeNumber = nil
    }

    func reset() {
        activeCall?.disconnect()
        activeCall = nil
        activeNumber = nil
        CallManager.shared.forceTerminate()
    }


    func cleanup() {
        activeCall = nil
        callInvite = nil
        activeNumber = nil

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - this polled /voice/calls/active
    // every ten seconds. That route does not exist, so it was a 404 loop for the
    // life of the app. Left as a no-op rather than deleted so the call sites and
    // handleRemoteCallUpdates stay in place for whenever the route lands.
    private func startActiveCallPolling() {
        pollingTask?.cancel()
    }

    private func handleRemoteCallUpdates(_ calls: [RemoteCallStatus]) {
        let line = LineManager.shared.activeLine
        for call in calls {
            persistCall(
                CallModel(
                    id: call.id,
                    number: call.number,
                    direction: "inbound",
                    status: call.status,
                    startedAt: Date(),
                    endedAt: call.status == "ended" ? Date() : nil
                ),
                line: line
            )
        }
    }

    private func updateCallStatus(id: String, status: String) {
        let context = PersistenceController.shared.container.viewContext
        let request = CallEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id)

        if let call = try? context.fetch(request).first {
            call.status = status
            if status == "completed" || status == "ended" {
                call.endedAt = Date()
            }
            try? context.save()
        }
    }

    func persistCall(_ call: CallModel, line: Line) {
        let context = PersistenceController.shared.container.viewContext
        let entity = CallEntity(context: context)
        entity.id = call.id
        entity.number = call.number
        entity.direction = call.direction
        entity.status = call.status
        entity.startedAt = call.startedAt
        entity.endedAt = call.endedAt
        entity.lineId = line.id
        try? context.save()
    }
}

extension VoiceService: @preconcurrency CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        activeCall?.disconnect()
        activeCall = nil
        activeNumber = nil
        CallManager.shared.forceTerminate()
    }
}

extension VoiceService: @preconcurrency CallDelegate {

    func callDidStartRinging(call: Call) {
#if DEBUG
        print("Call ringing")
#endif
    }

    func callDidConnect(call: Call) {
        CallManager.shared.callDidConnect()
    }

    func callDidDisconnect(call: Call, error: Error?) {
        CallStateManager.shared.reset()
        cleanup()

        if error != nil {
            CallManager.shared.callDidFail()
        } else {
            CallManager.shared.forceTerminate()
        }

        activeCall = nil
        activeNumber = nil
    }

    func callDidFailToConnect(call: Call, error: Error) {
        CallStateManager.shared.reset()
        cleanup()
        CallManager.shared.callDidFail()
        activeCall = nil
        activeNumber = nil
    }
}

extension VoiceService: @preconcurrency NotificationDelegate {

    // BOREAL_DIALER_MODULE_COMPILES_v4 - required by NotificationDelegate and
    // previously missing.
    func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: any Error) {
        guard callInvite?.callSid == cancelledCallInvite.callSid else { return }
        callInvite = nil
        CallStateManager.shared.transition(to: .ended)
        CallStateManager.shared.reset()
    }


    func callInviteReceived(callInvite: CallInvite) {
        if CallStateManager.shared.current() != .idle {
            callInvite.reject()
            return
        }

        guard CallStateManager.shared.transition(from: .idle, to: .ringing) else {
            callInvite.reject()
            return
        }

        self.callInvite = callInvite

        let uuid = callInvite.uuid
        let number = callInvite.from ?? "Unknown"

        handleIncomingCall(uuid: uuid, number: number)
        CallKitManager.shared.reportIncomingCall(uuid: uuid, handle: number)
    }
}
