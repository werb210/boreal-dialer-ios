import Foundation
import CallKit
import TwilioVoice
import AVFoundation

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
    @Published var isMuted = false
    @Published var isOnHold = false
    @Published var showKeypad = false

    var activeCallSid: String? {
        if case .active(let uuid) = state {
            return uuid.uuidString
        }
        if case .dialing(let uuid) = state {
            return uuid.uuidString
        }
        return nil
    }

    private var provider: CXProvider!
    private var timer: Timer?

    private override init() {
        super.init()
        configureCallKit()
    }

    private func configureCallKit() {
        // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - "Boreal Financial" is what iOS
        // prints under the caller on the lock screen, so it should be the name
        // a staff member would recognise at a glance.
        let config = CXProviderConfiguration(localizedName: "Boreal Financial")
        config.supportsVideo = false
        // V1 deliberately supports one external call. A second Twilio invite is
        // rejected deterministically by TwilioVoiceManager.
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.includesCallsInRecents = true
        config.supportedHandleTypes = [.phoneNumber, .generic]

        provider = CXProvider(configuration: config)
        provider.setDelegate(self, queue: nil)
    }

    func startCall(to number: String, uuid: UUID = UUID()) {
        guard case .idle = state else { return }
        requestMicrophonePermissionIfNeeded()
        state = .dialing(uuid)

        let handle = CXHandle(type: .phoneNumber, value: number)
        let start = CXStartCallAction(call: uuid, handle: handle)
        // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - names the call in iOS Recents.
        start.contactIdentifier = PhoneFormat.display(number)
        let transaction = CXTransaction(action: start)

        CXCallController().request(transaction) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.handleFailure()
            }
        }

        let capturedLine = activeLine
        Telemetry.event("call_start", metadata: ["callId": uuid.uuidString, "silo": silo.rawValue])
        // BOREAL_DIALER_JOIN_CONFERENCE_v46 - build the conference first so the
        // SDK leg can join it. A plain call remains the fallback if setup fails.
        Task { @MainActor in
            let ok = await ConferenceSession.shared.start(to: number)
            let friendly = ok ? ConferenceSession.shared.conferenceFriendly : nil
            TwilioVoiceManager.shared.startCall(
                uuid: uuid, to: number, line: capturedLine, conferenceFriendly: friendly
            )
        }
    }

    // BOREAL_DIALER_JOIN_CONFERENCE_v46 - create and join an internal call,
    // while also reporting the initiating leg to CallKit.
    func startInternalCall(staffIdentity: String, displayName: String) {
        guard case .idle = state else { return }

        let uuid = UUID()
        state = .dialing(uuid)

        let handle = CXHandle(type: .generic, value: displayName)
        let start = CXStartCallAction(call: uuid, handle: handle)
        start.contactIdentifier = displayName
        let transaction = CXTransaction(action: start)

        CXCallController().request(transaction) { [weak self] error in
            guard let self else { return }
            if error != nil { self.handleFailure() }
        }

        Telemetry.event(
            "quick_call_start", metadata: ["staff": staffIdentity, "silo": silo.rawValue]
        )

        Task { @MainActor in
            let ok = await ConferenceSession.shared.startInternal(staffIdentity: staffIdentity)
            guard ok, let friendly = ConferenceSession.shared.conferenceFriendly else {
                self.handleFailure()
                return
            }
            TwilioVoiceManager.shared.startCall(
                uuid: uuid, to: displayName, conferenceFriendly: friendly
            )
        }
    }

    func reportIncoming(uuid: UUID, handle: String) {
        guard case .idle = state else { return }

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - a readable number until the
        // contact lookup comes back. iOS shows this verbatim.
        update.localizedCallerName = PhoneFormat.display(handle)
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            guard let self else { return }
            if error == nil {
                self.state = .ringing(uuid)
                WatchBridge.shared.send(WatchEvent(kind: .incomingCall,
                                                   callId: uuid.uuidString,
                                                   displayName: "",
                                                   handle: handle))
                // Named after the fact. Reporting must not wait on the network:
                // iOS terminates the app if a VoIP push does not report a call
                // almost immediately.
                self.nameIncomingCall(uuid: uuid, handle: handle)
            }
        }
    }

    // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - resolve the number to a CRM contact
    // and push the name into the ringing CallKit screen.
    private func nameIncomingCall(uuid: UUID, handle: String) {
        Task { [weak self] in
            guard let self else { return }
            // BOREAL_DIALER_RESOLVE_CALLER_CONTRACT_v45
            do {
                let resolved = try await CallerResolver.resolve(phone: handle)
                guard let display = resolved.display else { return }

                let update = CXCallUpdate()
                update.localizedCallerName = display
                self.provider.reportCall(with: uuid, updated: update)
                WatchBridge.shared.send(WatchEvent(kind: .incomingCall,
                                                   callId: uuid.uuidString,
                                                   displayName: display,
                                                   handle: handle))
            } catch {
                // An unresolved number keeps the formatted number already shown.
            }
        }
    }

    func setActiveLine(_ line: Line) {
        activeLine = line
        silo = Silo(rawValue: line.rawValue) ?? .bf
    }

    func toggleMute() {
        isMuted = TwilioVoiceManager.shared.setMuted(!isMuted)
        Telemetry.event("call_mute_toggled", metadata: ["isMuted": "\(isMuted)"])
    }

    func toggleHold(onHold: Bool) {
        isOnHold = TwilioVoiceManager.shared.setOnHold(onHold)
        Telemetry.event("call_hold_toggled", metadata: ["isOnHold": "\(onHold)"])
    }

    func forceTerminate() {
        TwilioVoiceManager.shared.disconnect()
        finishCall(status: .ended)
    }

    private func requestMicrophonePermissionIfNeeded() {
        if AVAudioSession.sharedInstance().recordPermission == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
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
        // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - /voice/calls/active does not
        // exist, so there is nothing to reconcile against.
        let serverCalls: [RemoteCallStatus]? = nil

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

    func endReportedCall(uuid: UUID, reason: CXCallEndedReason = .remoteEnded) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        WatchBridge.shared.send(WatchEvent(kind: .missedCall,
                                           callId: uuid.uuidString,
                                           displayName: "", handle: ""))
        if case .ringing(let active) = state, active == uuid {
            finishCall(status: .ended)
        }
    }

    private func finishCall(status: State) {
        stopTimer()
        state = status
        isMuted = false
        isOnHold = false
        showKeypad = false

        // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - the number and SID come from the
        // Twilio manager; without a number there is nothing to resolve a
        // contact against and the server would reject the event.
        let number = TwilioVoiceManager.shared.activeNumber
        let sid = activeCallSid
        let seconds = callDuration
        Task {
            try? await API.logCall(
                duration: seconds,
                status: "\(status)",
                number: number,
                callSid: sid
            )
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

extension VoiceEngine: @preconcurrency CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        TwilioVoiceManager.shared.disconnect()
        stopTimer()
        state = .idle
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        requestMicrophonePermissionIfNeeded()
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

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        isMuted = TwilioVoiceManager.shared.setMuted(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        isOnHold = TwilioVoiceManager.shared.setOnHold(action.isOnHold)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        guard TwilioVoiceManager.shared.sendDigits(action.digits) else { action.fail(); return }
        action.fulfill()
    }
}
