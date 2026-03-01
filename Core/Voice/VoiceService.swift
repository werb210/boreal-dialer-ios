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

    func handleIncomingCall(_ call: Call) {
        currentDirection = .inbound
        callStartDate = Date()

        activeCall = call
        activeCall?.delegate = self
        activeNumber = call.from ?? "Unknown"

        let uuid = UUID()
        guard CallManager.shared.startIncomingCall(from: activeNumber ?? "Unknown", uuid: uuid) else {
            return
        }
        CallKitManager.shared.reportIncomingCall(uuid: uuid, number: activeNumber ?? "Unknown")

        persistCall(
            CallModel(
                id: uuid.uuidString,
                number: activeNumber ?? "Unknown",
                direction: "inbound",
                status: "ringing",
                startedAt: callStartDate ?? Date(),
                endedAt: nil
            ),
            line: LineManager.shared.activeLine
        )
    }

    func endCall() {
        CallManager.shared.endCall()
    }

    func endCall(uuid: UUID) {
        guard CallManager.shared.activeCallUUID == uuid else { return }

        activeCall?.disconnect()
        Task {
            try? await API.endCall(uuid: uuid.uuidString)
        }
        activeNumber = nil
    }

    func answerIncomingCall() {
        activeCall?.accept()
    }

    func rejectIncomingCall() {
        activeCall?.reject()
        CallManager.shared.callDidFail()
    }

    func reset() {
        activeCall?.disconnect()
        activeCall = nil
        activeNumber = nil
        CallManager.shared.forceTerminate()
    }

    private func startActiveCallPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                do {
                    let activeCalls = try await NetworkManager.shared.fetchActiveCalls()
                    handleRemoteCallUpdates(activeCalls)
                } catch {
                    continue
                }
            }
        }
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

extension VoiceService: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        activeCall?.disconnect()
        activeCall = nil
        activeNumber = nil
        CallManager.shared.forceTerminate()
    }
}

extension VoiceService: CallDelegate {

    func callDidStartRinging(_ call: Call) {
        print("Call ringing")
    }

    func callDidConnect(_ call: Call) {
        CallManager.shared.callDidConnect()
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
        if error != nil {
            CallManager.shared.callDidFail()
        } else {
            CallManager.shared.forceTerminate()
        }

        activeCall = nil
        activeNumber = nil
    }

    func callDidFailToConnect(_ call: Call, error: Error) {
        CallManager.shared.callDidFail()
        activeCall = nil
        activeNumber = nil
    }
}

extension VoiceService: NotificationDelegate {

    func callInviteReceived(_ callInvite: CallInvite) {
        let call = callInvite.accept(with: self)
        handleIncomingCall(call)
    }
}
