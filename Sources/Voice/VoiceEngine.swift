import Foundation
import CallKit
import TwilioVoice
import AVFoundation

// BOREAL_DIALER_v817_CALLS - one place for the microphone permission. The
// deployment target is iOS 16; AVAudioApplication replaces the AVAudioSession
// API from iOS 17.
enum MicrophonePermission {
    enum Status {
        case granted
        case denied
        case undetermined
    }

    static let deniedMessage = "Microphone access is off for Boreal Dialer. Turn it on in Settings > Boreal Dialer > Microphone to make and take calls."

    static var status: Status {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        }
    }

    /// `completion` may run on any queue.
    static func request(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    /// Prompts once, at sign-in / app start, so the first call is not the prompt.
    static func requestIfNeeded() {
        guard status == .undetermined else { return }
        request { _ in }
    }
}

@MainActor
final class VoiceEngine: NSObject, ObservableObject {

    // BOREAL_DIALER_PRESENT_DISPOSITION_v224
    /// The most recently ended call, for the outcome sheet. Cleared once the
    /// sheet is dismissed so returning to the dialer does not re-present it.
    @Published var finishedCall: FinishedCall?

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

    @Published private(set) var state: State = .idle {
        didSet { syncLiveActivity() } // BOREAL_DIALER_LIVE_ACTIVITY_WIRE_v1
    }
    private var currentHandle: String = "" // BOREAL_DIALER_LIVE_ACTIVITY_WIRE_v1
    @Published private(set) var callDuration: Int = 0
    @Published var activeLine: Line = .bf
    @Published var silo: Silo = .bf
    @Published var isMuted = false
    @Published var isOnHold = false
    @Published var showKeypad = false
    // BOREAL_DIALER_v817_CALLS - why the last call could not be placed (shown by
    // the dialer). Cleared when the alert is dismissed.
    @Published var callError: String?

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
    // BOREAL_DIALER_v817_CALLS - one long-lived controller for every CallKit
    // transaction (start and end), rather than a throwaway one per request.
    private let callController = CXCallController()
    // BOREAL_DIALER_v817_CALLS - the Twilio audio device, installed once. It is
    // disabled until CallKit activates the audio session (provider didActivate)
    // and disabled again when CallKit deactivates it, so Twilio never runs
    // audio on a session CallKit has not handed over.
    let audioDevice = DefaultAudioDevice()

    // BOREAL_DIALER_v817_CALLS - what a requested CXStartCallAction should
    // dial. The action handler starts the Twilio leg from this.
    private enum PendingOutgoing {
        case pstn(number: String, line: Line)
        case internalCall(staffIdentity: String, displayName: String)
    }
    private var pendingOutgoing: [UUID: PendingOutgoing] = [:]

    private override init() {
        super.init()
        // BOREAL_DIALER_v817_CALLS - must be set before any connect or accept.
        TwilioVoiceSDK.audioDevice = audioDevice
        audioDevice.isEnabled = false
        configureCallKit()
    }

    private func configureCallKit() {
        // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - "Boreal Financial" is what iOS
        // prints under the caller on the lock screen, so it should be the name
        // a staff member would recognise at a glance.
        // The deprecated localized-name initializer is no longer necessary:
        // CallKit obtains the provider name from the app's display name.
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        // V1 deliberately supports one external call. A second Twilio invite is
        // rejected deterministically by TwilioVoiceManager.
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.includesCallsInRecents = true
        config.supportedHandleTypes = [.phoneNumber, .generic]

        provider = CXProvider(configuration: config)
        provider.setDelegate(self, queue: nil)
        // BOREAL_DIALER_CALLKIT_REPORTER_v789 - every push reports through this provider.
        CallKitReporter.shared.provider = CXProviderReporting(provider: provider)
    }

    // BOREAL_DIALER_CALLKIT_REPORTER_v789 - false while ringing, dialing, active
    // and during the 1.5 s ended/failed cooldown in finishCall.
    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    func startCall(to rawNumber: String, uuid: UUID = UUID()) {
        guard case .idle = state else { return }
        // BOREAL_DIALER_v817_CALLS - Twilio dials E.164 only.
        let number = PhoneFormat.e164(rawNumber)
        guard !number.isEmpty else { return }
        // BOREAL_DIALER_v817_CALLS - no microphone, no call: fail fast with a
        // reason instead of connecting a silent call. An undetermined
        // permission prompts and places the call once granted.
        guard microphoneReady(retry: { VoiceEngine.shared.startCall(to: number, uuid: uuid) }) else { return }
        callError = nil
        state = .dialing(uuid)

        currentHandle = PhoneFormat.display(number)
        let capturedLine = activeLine
        pendingOutgoing[uuid] = .pstn(number: number, line: capturedLine)
        // BOREAL_DIALER_v817_CALLS - no Twilio audio until CallKit activates the session.
        audioDevice.isEnabled = false

        let handle = CXHandle(type: .phoneNumber, value: number)
        let start = CXStartCallAction(call: uuid, handle: handle)
        // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - names the call in iOS Recents.
        start.contactIdentifier = PhoneFormat.display(number)
        let transaction = CXTransaction(action: start)

        // BOREAL_DIALER_v817_CALLS - CallKit performs the start action and the
        // Twilio leg is started from provider(_:perform: CXStartCallAction), so
        // CallKit owns the call and its audio session. Starting Twilio here in
        // parallel left the start action unhandled and the call "failed".
        callController.request(transaction) { [weak self] error in
            let failed = error != nil
            Task { @MainActor in
                guard let self else { return }
                if failed {
                    self.handleFailure()
                }
            }
        }

        Telemetry.event("call_start", metadata: ["callId": uuid.uuidString, "silo": silo.rawValue])
    }

    // BOREAL_DIALER_JOIN_CONFERENCE_v46 - create and join an internal call,
    // while also reporting the initiating leg to CallKit.
    func startInternalCall(staffIdentity: String, displayName: String) {
        guard case .idle = state else { return }
        // BOREAL_DIALER_v817_CALLS - same microphone gate as startCall.
        guard microphoneReady(retry: {
            VoiceEngine.shared.startInternalCall(staffIdentity: staffIdentity, displayName: displayName)
        }) else { return }
        callError = nil

        let uuid = UUID()
        state = .dialing(uuid)

        currentHandle = displayName
        pendingOutgoing[uuid] = .internalCall(staffIdentity: staffIdentity, displayName: displayName)
        // BOREAL_DIALER_v817_CALLS - no Twilio audio until CallKit activates the session.
        audioDevice.isEnabled = false

        let handle = CXHandle(type: .generic, value: displayName)
        let start = CXStartCallAction(call: uuid, handle: handle)
        start.contactIdentifier = displayName
        let transaction = CXTransaction(action: start)

        // BOREAL_DIALER_v817_CALLS - the conference and Twilio leg are started
        // by provider(_:perform: CXStartCallAction).
        callController.request(transaction) { [weak self] error in
            let failed = error != nil
            Task { @MainActor in
                guard let self else { return }
                if failed { self.handleFailure() }
            }
        }

        Telemetry.event(
            "quick_call_start", metadata: ["staff": staffIdentity, "silo": silo.rawValue]
        )
    }

    // BOREAL_DIALER_v817_CALLS - true when the microphone is granted. Denied:
    // sets callError and returns false. Undetermined: prompts, returns false,
    // and runs `retry` on the main actor if the user grants it.
    private func microphoneReady(retry: @escaping @MainActor () -> Void) -> Bool {
        switch MicrophonePermission.status {
        case .granted:
            return true
        case .denied:
            callError = MicrophonePermission.deniedMessage
            Telemetry.event("call_blocked", metadata: ["reason": "microphone_denied"])
            return false
        case .undetermined:
            MicrophonePermission.request { granted in
                Task { @MainActor in
                    if granted {
                        retry()
                    } else {
                        VoiceEngine.shared.callError = MicrophonePermission.deniedMessage
                    }
                }
            }
            return false
        }
    }

    // BOREAL_DIALER_v817_CALLS - the in-call hang-up button. Ending through a
    // CXEndCallAction keeps CallKit's call list in step; ending only the
    // Twilio leg left a stale CallKit call that blocked every later call.
    func hangUp() {
        guard let uuid = liveCallUUID else {
            forceTerminate()
            return
        }
        let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
        callController.request(transaction) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                // CallKit refused (it no longer knows the call): end it here.
                self?.forceTerminate()
            }
        }
    }

    // BOREAL_DIALER_v817_CALLS - answering from the Watch (or anywhere but the
    // CallKit screen) goes through a CXAnswerCallAction too. Accepting the
    // Twilio invite directly never had CallKit activate the audio session, so
    // the Twilio audio device stayed off and the call was silent.
    func answer(uuid: UUID) {
        guard case .ringing(let ringing) = state, ringing == uuid else { return }
        let transaction = CXTransaction(action: CXAnswerCallAction(call: uuid))
        callController.request(transaction) { error in
            guard let error else { return }
            Telemetry.event("call_answer_failed", metadata: ["error": error.localizedDescription])
        }
    }

    // BOREAL_DIALER_v817_CALLS - the CallKit UUID of the call in progress.
    private var liveCallUUID: UUID? {
        switch state {
        case .dialing(let uuid), .ringing(let uuid), .active(let uuid):
            return uuid
        case .idle, .ended, .failed:
            return nil
        }
    }

    /// `onResult` receives true once CallKit is ringing the call.
    func reportIncoming(uuid: UUID, handle: String, onResult: ((Bool) -> Void)? = nil) {
        // BOREAL_DIALER_CALLKIT_REPORTER_v789 - this used to return silently
        // when not idle (including the 1.5 s cooldown after a call), which is a
        // VoIP push with no reported call. Report it and end it at once.
        guard case .idle = state else {
            CallKitReporter.shared.reportPlaceholder(handle: handle, reason: .unanswered)
            onResult?(false)
            return
        }

        // BOREAL_DIALER_v817_CALLS - no Twilio audio until CallKit activates the
        // session on answer (provider didActivate).
        audioDevice.isEnabled = false

        let update = CXCallUpdate()
        currentHandle = PhoneFormat.display(handle)
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - a readable number until the
        // contact lookup comes back. iOS shows this verbatim.
        update.localizedCallerName = PhoneFormat.display(handle)
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true

        // Reported synchronously; the ringing state is applied when CallKit
        // answers, on the provider's (main) queue.
        CallKitReporter.shared.reportRinging(uuid: uuid, handle: handle, update: update) { [weak self] succeeded in
            guard let self else { return }
            if succeeded {
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
            onResult?(succeeded)
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
                CallKitReporter.shared.reportUpdated(uuid: uuid, update: update)
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
        // BOREAL_DIALER_v817_CALLS - tell CallKit the call is over, or it keeps
        // a stale call that (with one call group) blocks every later call.
        // Nothing to end when idle - and nothing to log.
        guard let uuid = liveCallUUID else { return }
        CallKitReporter.shared.reportEnded(uuid: uuid, reason: .remoteEnded)
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
        // BOREAL_DIALER_v817_CALLS - an outgoing call is "connected" for CallKit
        // (lock screen timer, Recents duration) once Twilio connects.
        if case .dialing(let dialing) = state, dialing == uuid {
            provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        }
        stopTimer()
        startTimer()
        state = .active(uuid)
    }

    // BOREAL_DIALER_LIVE_ACTIVITY_WIRE_v1 - one hook off state: show on connect, clear on end.
    private func syncLiveActivity() {
        switch state {
        case .active:
            CallLiveActivityController.shared.start(handle: currentHandle.isEmpty ? "Call" : currentHandle,
                                                    line: activeLine.rawValue.uppercased(),
                                                    status: "Connected")
        case .idle, .ended, .failed:
            CallLiveActivityController.shared.end()
        default:
            break
        }
    }

    func handleFailure() {
        // BOREAL_DIALER_v817_CALLS - report the failure to CallKit; a call it
        // still thinks is up blocks every later call ("Call failed"). Ignored
        // once the call has already finished (a late Twilio callback after a
        // local hang-up) so it is not logged twice.
        guard let uuid = liveCallUUID else { return }
        CallKitReporter.shared.reportEnded(uuid: uuid, reason: .failed)
        finishCall(status: .failed)
    }

    func handleDisconnect() {
        // BOREAL_DIALER_v817_CALLS - the remote side hung up: report it to
        // CallKit. A local hang-up has already finished the call through
        // CXEndCallAction, so its late Twilio callback lands here and stops.
        guard let uuid = liveCallUUID else { return }
        Telemetry.event("call_end", metadata: ["duration": "\(callDuration)"])
        CallKitReporter.shared.reportEnded(uuid: uuid, reason: .remoteEnded)
        finishCall(status: .ended)
    }

    // BOREAL_DIALER_PRESENT_DISPOSITION_v224
    // VoiceEngine owns call state but not the Twilio Call instance. The SDK
    // delegate publishes its stable CallSid through this UI-neutral hook.
    func publishFinishedCall(callSid: String?) {
        finishedCall = callSid.map { FinishedCall(callSid: $0, endedAt: Date()) }
    }

    func endReportedCall(uuid: UUID, reason: CXCallEndedReason = .remoteEnded) {
        CallKitReporter.shared.reportEnded(uuid: uuid, reason: reason)
        WatchBridge.shared.send(WatchEvent(kind: .missedCall,
                                           callId: uuid.uuidString,
                                           displayName: "", handle: ""))
        if case .ringing(let active) = state, active == uuid {
            finishCall(status: .ended)
        }
    }

    private func finishCall(status: State) {
        pendingOutgoing.removeAll() // BOREAL_DIALER_v817_CALLS
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
            // BOREAL_DIALER_OFFLINE_v303 - a call that ends with no signal is logged when it returns.
            do {
                try await API.logCall(
                    duration: seconds,
                    status: "\(status)",
                    number: number,
                    callSid: sid
                )
            } catch {
                if OfflineQueue.isOffline(error) {
                    API.queueCallLog(duration: seconds, status: "\(status)", number: number, callSid: sid)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // BOREAL_DIALER_v817_CALLS - a new call may have started inside the
            // cooldown; only an ended/failed state goes back to idle.
            switch self.state {
            case .ended, .failed:
                self.state = .idle
            default:
                break
            }
            // BOREAL_DIALER_v817_CALLS - push registration is skipped while a
            // call is up; retry it now so the phone keeps ringing.
            VoiceManager.shared.retryRegistrationAfterCall()
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
        audioDevice.isEnabled = false // BOREAL_DIALER_v817_CALLS
        pendingOutgoing.removeAll() // BOREAL_DIALER_v817_CALLS
        TwilioVoiceManager.shared.disconnect()
        stopTimer()
        state = .idle
    }

    // BOREAL_DIALER_v817_CALLS - outgoing calls. There was no handler, so every
    // CXStartCallAction timed out and CallKit failed the call. Category only
    // here (CallKit activates the session), report connecting, fulfil, then
    // start the Twilio leg with this UUID. The action is fulfilled at once (as
    // Twilio's CallKit reference does) so a slow conference setup cannot time
    // it out; a setup that fails later ends the call through handleFailure,
    // which reports it to CallKit as failed.
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let uuid = action.callUUID
        guard let pending = pendingOutgoing.removeValue(forKey: uuid),
              case .dialing(let dialing) = state, dialing == uuid else {
            action.fail()
            return
        }
        audioDevice.isEnabled = false
        TwilioVoiceManager.shared.configureAudioSessionForCall()
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
        action.fulfill()

        Task { @MainActor in
            switch pending {
            case .pstn(let number, let line):
                // BOREAL_DIALER_JOIN_CONFERENCE_v46 - build the conference first
                // so the SDK leg can join it. A plain call remains the fallback.
                let ok = await ConferenceSession.shared.start(to: number)
                // BOREAL_DIALER_v817_CALLS - hung up or failed during setup:
                // do not go on and dial.
                guard self.isDialing(uuid) else { return }
                let friendly = ok ? ConferenceSession.shared.conferenceFriendly : nil
                TwilioVoiceManager.shared.startCall(
                    uuid: uuid, to: number, line: line, conferenceFriendly: friendly
                )
            case .internalCall(let staffIdentity, let displayName):
                let ok = await ConferenceSession.shared.startInternal(staffIdentity: staffIdentity)
                guard self.isDialing(uuid) else { return }
                guard ok, let friendly = ConferenceSession.shared.conferenceFriendly else {
                    self.handleFailure()
                    return
                }
                TwilioVoiceManager.shared.startCall(
                    uuid: uuid, to: displayName, conferenceFriendly: friendly
                )
            }
        }
    }

    // BOREAL_DIALER_v817_CALLS
    private func isDialing(_ uuid: UUID) -> Bool {
        if case .dialing(let dialing) = state, dialing == uuid { return true }
        return false
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // BOREAL_DIALER_v817_CALLS - category only; CallKit activates the session.
        MicrophonePermission.requestIfNeeded()
        audioDevice.isEnabled = false
        TwilioVoiceManager.shared.configureAudioSessionForCall()
        TwilioVoiceManager.shared.accept()
        startTimer()
        state = .active(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // BOREAL_DIALER_v817_CALLS - a local hang-up (CallKit UI, in-app button,
        // Watch). Disconnect the Twilio leg (or reject a ringing invite) and
        // finish the call; CallKit ends its own call when this is fulfilled.
        pendingOutgoing.removeValue(forKey: action.callUUID)
        TwilioVoiceManager.shared.disconnect()
        if liveCallUUID != nil {
            Telemetry.event("call_end", metadata: ["duration": "\(callDuration)"])
            finishCall(status: .ended)
        }
        action.fulfill()
    }

    // BOREAL_DIALER_v817_CALLS - CallKit hands over the audio session: only now
    // may Twilio start audio.
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        audioDevice.isEnabled = true
    }

    // BOREAL_DIALER_v817_CALLS - CallKit took the audio session back.
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        audioDevice.isEnabled = false
    }

    // BOREAL_DIALER_v817_CALLS - an action CallKit gave up on (e.g. a start
    // whose setup never finished) must not leave a half-started call behind.
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        Telemetry.event("callkit_action_timed_out", metadata: ["action": String(describing: type(of: action))])
        if action is CXStartCallAction || action is CXAnswerCallAction {
            TwilioVoiceManager.shared.disconnect()
            handleFailure()
        }
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
