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
    // BOREAL_DIALER_v829_RELIABILITY - answered, but Twilio has not connected the audio yet. The call used to show
    // "connected" with the timer running from the tap, so the normal second or two of setup looked like a dead call.
    @Published private(set) var isConnecting = false
    // BOREAL_DIALER_v829_RELIABILITY - an outgoing call whose customer's phone is ringing (the staff leg is in the
    // call hearing ringback). The call counts as connected only when they answer.
    @Published private(set) var remoteRinging = false
    private var answerTappedAt: Date?
    private var connectWatchdog: Task<Void, Never>?
    private var calleeWatch: Task<Void, Never>?
    /// The number of the call in progress, kept for the call log (Twilio's copy is cleared on hang-up).
    private var currentNumber: String?
    // BOREAL_DIALER_v831_DIALER_POLISH
    /// "inbound" or "outbound", for the call log.
    private var currentDirection = "outbound"
    /// When the call connected (audio up, or the customer answered); nil while it rings.
    private var connectedAt: Date?
    /// Name and length of the call that just ended, kept for its outcome sheet (the call's state is cleared first).
    private var endedDetails: (name: String?, seconds: Int)?
    /// Outcome sheets waiting behind the one on screen: a second call no longer replaces an unsaved outcome.
    private var outcomeQueue: [FinishedCall] = []
    /// How long an answered call may take to connect before it is ended with a reason.
    static let connectTimeoutSeconds: UInt64 = 12
    // BOREAL_DIALER_v830_DIALER_CONTROLS
    /// An extension to send as tones once the outgoing call is answered.
    private var pendingTones: String?
    /// The call's audio is on the iPhone speaker.
    @Published private(set) var isSpeakerOn = false
    /// Twilio lost the media connection and is reconnecting (bad signal); the call is not over.
    @Published private(set) var isReconnecting = false
    /// Tones typed on the in-call keypad, shown above it.
    @Published private(set) var sentTones = ""
    private var routeObserver: NSObjectProtocol?

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

    // BOREAL_DIALER_v831_DIALER_POLISH - a call is ringing, being placed, or up. The 1.5 s "ended" pause after a call
    // is not a call: taps to call were ignored in it and a call arriving in it was turned away.
    var isOnCall: Bool { liveCallUUID != nil }
    /// The CallKit id of the call in progress.
    var currentCallUUID: UUID? { liveCallUUID }

    private var readyForNewCall: Bool {
        switch state {
        case .idle, .ended, .failed: return true
        default: return false
        }
    }

    func startCall(to rawNumber: String, uuid: UUID = UUID()) {
        guard readyForNewCall else { return } // BOREAL_DIALER_v831_DIALER_POLISH
        // BOREAL_DIALER_v830_DIALER_CONTROLS - "403-555-0142 ext 123": dial the number, send 123 once connected.
        let parts = DialString.split(rawNumber)
        // BOREAL_DIALER_v817_CALLS - Twilio dials E.164 only.
        let number = PhoneFormat.e164(parts.number)
        guard !number.isEmpty else { return }
        // BOREAL_DIALER_v817_CALLS - no microphone, no call: fail fast with a
        // reason instead of connecting a silent call. An undetermined
        // permission prompts and places the call once granted.
        guard microphoneReady(retry: { VoiceEngine.shared.startCall(to: rawNumber, uuid: uuid) }) else { return }
        callError = nil
        state = .dialing(uuid)
        pendingTones = parts.extensionDigits // BOREAL_DIALER_v830_DIALER_CONTROLS
        currentNumber = number // BOREAL_DIALER_v829_RELIABILITY
        beginCallRecord(direction: "outbound") // BOREAL_DIALER_v831_DIALER_POLISH

        currentHandle = PhoneFormat.display(number)
        CallerCardStore.shared.clear() // BOREAL_DIALER_v821 - the in-call screen fetches this call's card.
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
        guard readyForNewCall else { return } // BOREAL_DIALER_v831_DIALER_POLISH
        // BOREAL_DIALER_v817_CALLS - same microphone gate as startCall.
        guard microphoneReady(retry: {
            VoiceEngine.shared.startInternalCall(staffIdentity: staffIdentity, displayName: displayName)
        }) else { return }
        callError = nil

        let uuid = UUID()
        state = .dialing(uuid)
        currentNumber = nil
        beginCallRecord(direction: "outbound") // BOREAL_DIALER_v831_DIALER_POLISH

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
    /// BOREAL_DIALER_v821 - `card` comes from the Twilio invite's customParameters (callerName, callerCompany,
    /// callerStage, contactId). It is local data, so the first CallKit report already shows the caller's name.
    func reportIncoming(uuid: UUID, handle: String, card: CallerCard? = nil, onResult: ((Bool) -> Void)? = nil) {
        // BOREAL_DIALER_CALLKIT_REPORTER_v789 - this used to return silently
        // when not idle (including the 1.5 s cooldown after a call), which is a
        // VoIP push with no reported call. Report it and end it at once.
        guard readyForNewCall else { // BOREAL_DIALER_v831_DIALER_POLISH - the pause after a call is not busy
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
        // BOREAL_DIALER_v821 - the invite's callerName when the server sent one.
        let inviteCard = card?.isDisplayable == true ? card : nil
        update.localizedCallerName = inviteCard?.callKitName ?? PhoneFormat.display(handle)
        if let inviteCard {
            CallerCardStore.shared.set(inviteCard, handle: handle)
        } else {
            CallerCardStore.shared.clear()
        }
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
                self.currentNumber = handle // BOREAL_DIALER_v829_RELIABILITY
                self.beginCallRecord(direction: "inbound") // BOREAL_DIALER_v831_DIALER_POLISH
                // BOREAL_DIALER_v821 - the Watch shows the name and the stage (WatchEvent.preview) when known.
                WatchBridge.shared.send(WatchEvent(kind: .incomingCall,
                                                   callId: uuid.uuidString,
                                                   displayName: inviteCard?.callKitName ?? "",
                                                   handle: handle,
                                                   preview: inviteCard?.stage ?? ""))
                // Named after the fact. Reporting must not wait on the network:
                // iOS terminates the app if a VoIP push does not report a call
                // almost immediately.
                // BOREAL_DIALER_v821 - no lookup when the invite already named the caller.
                if inviteCard == nil {
                    self.nameIncomingCall(uuid: uuid, handle: handle)
                }
            }
            onResult?(succeeded)
        }
    }

    // BOREAL_DIALER_CALLKIT_IDENTITY_v38 - resolve the number to a CRM contact
    // and push the name into the ringing CallKit screen.
    private func nameIncomingCall(uuid: UUID, handle: String) {
        Task { [weak self] in
            guard let self else { return }
            // BOREAL_DIALER_v821 - the caller card first (it also feeds the in-call screen and the Watch's stage line);
            // the v45 resolve-caller lookup below is the fallback when it cannot be fetched or found nobody.
            if let card = try? await CallerCardService.fetch(phone: handle), let display = card.callKitName {
                // Answered already is fine (the in-call screen reads the card); a finished call is not.
                guard self.liveCallUUID == uuid else { return }
                CallerCardStore.shared.set(card, handle: handle)
                let update = CXCallUpdate()
                update.localizedCallerName = display
                CallKitReporter.shared.reportUpdated(uuid: uuid, update: update)
                WatchBridge.shared.send(WatchEvent(kind: .incomingCall,
                                                   callId: uuid.uuidString,
                                                   displayName: display,
                                                   handle: handle,
                                                   preview: card.stage ?? ""))
                return
            }
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
        // BOREAL_DIALER_v830_DIALER_CONTROLS - through CallKit, so the lock screen and the app agree on mute.
        let wanted = !isMuted
        guard let uuid = liveCallUUID else {
            isMuted = TwilioVoiceManager.shared.setMuted(wanted)
            return
        }
        callController.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: wanted))) { error in
            guard error != nil else { return }
            Task { @MainActor in
                VoiceEngine.shared.isMuted = TwilioVoiceManager.shared.setMuted(wanted)
            }
        }
        Telemetry.event("call_mute_toggled", metadata: ["isMuted": "\(wanted)"])
    }

    // BOREAL_DIALER_v830_DIALER_CONTROLS - the in-call keypad: tones go through CallKit (CXPlayDTMFCallAction), which
    // sends them on the Twilio leg (provider perform CXPlayDTMFCallAction).
    func sendTones(_ digits: String) {
        let tones = digits.filter { $0.isNumber || $0 == "*" || $0 == "#" }
        guard !tones.isEmpty, let uuid = liveCallUUID else { return }
        sentTones = String((sentTones + tones).suffix(24))
        // A Boreal (conference) call: the other party's leg gets the tones from BF-Server.
        if ConferenceSession.shared.isActive {
            Task { @MainActor in _ = await ConferenceSession.shared.sendTones(tones) }
            return
        }
        let action = CXPlayDTMFCallAction(call: uuid, digits: tones, type: .singleTone)
        callController.request(CXTransaction(action: action)) { error in
            guard error != nil else { return }
            Task { @MainActor in _ = TwilioVoiceManager.shared.sendDigits(tones) }
        }
    }

    // BOREAL_DIALER_v830_DIALER_CONTROLS - resume a call iOS put on hold (e.g. "Hold & Accept" for a mobile call).
    func resumeFromHold() {
        guard let uuid = liveCallUUID else { return }
        callController.request(CXTransaction(action: CXSetHeldCallAction(call: uuid, onHold: false))) { error in
            guard error != nil else { return }
            Task { @MainActor in
                VoiceEngine.shared.isOnHold = TwilioVoiceManager.shared.setOnHold(false)
            }
        }
    }

    // BOREAL_DIALER_v830_DIALER_CONTROLS - speakerphone. Bluetooth / AirPods are picked with the route button.
    func toggleSpeaker() {
        let wanted = !isSpeakerOn
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(wanted ? .speaker : .none)
            isSpeakerOn = wanted
        } catch {
            Telemetry.event("speaker_toggle_failed", metadata: ["error": error.localizedDescription])
        }
    }

    /// Keeps the speaker button true to the real route (AirPods connecting, the route picker, CallKit's own button).
    private func observeAudioRoute() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { _ in
            let onSpeaker = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
            Task { @MainActor in VoiceEngine.shared.isSpeakerOn = onSpeaker }
        }
    }

    // BOREAL_DIALER_v830_DIALER_CONTROLS - Twilio's reconnect callbacks (TwilioVoiceManager).
    func setReconnecting(_ reconnecting: Bool) {
        isReconnecting = reconnecting
        Telemetry.event(reconnecting ? "call_reconnecting" : "call_reconnected", callRef: TwilioVoiceManager.shared.lastCallSid)
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
        connectWatchdog?.cancel()
        connectWatchdog = nil
        let sid = TwilioVoiceManager.shared.lastCallSid
        if isConnecting {
            // BOREAL_DIALER_v829_RELIABILITY - an answered incoming call: audio is up now, so the timer starts now.
            isConnecting = false
            let ms = answerTappedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
            Telemetry.event("call_connected", metadata: ["direction": "inbound", "answerToConnectMs": "\(ms)"], callRef: sid)
        }
        // BOREAL_DIALER_v829_RELIABILITY - an outgoing conference call: the staff leg is in the call, but the customer's
        // phone is still ringing. Stay "Calling" (with ringback) until they answer, then count it as connected.
        if case .dialing(let dialing) = state, dialing == uuid, ConferenceSession.shared.awaitingCallee {
            remoteRinging = true
            Telemetry.event("staff_leg_joined", metadata: ["direction": "outbound"], callRef: sid)
            watchCallee(uuid: uuid)
            return
        }
        markOutgoingConnected(uuid: uuid)
    }

    /// The customer answered (or the call needed no wait): CallKit timer, Recents duration and our timer start now.
    private func markOutgoingConnected(uuid: UUID) {
        remoteRinging = false
        // BOREAL_DIALER_v817_CALLS - an outgoing call is "connected" for CallKit
        // (lock screen timer, Recents duration) once Twilio connects.
        if case .dialing(let dialing) = state, dialing == uuid {
            provider.reportOutgoingCall(with: uuid, connectedAt: Date())
            Telemetry.event("call_connected", metadata: ["direction": "outbound"], callRef: TwilioVoiceManager.shared.lastCallSid)
        }
        stopTimer()
        startTimer()
        state = .active(uuid)
        // BOREAL_DIALER_v830_DIALER_CONTROLS - the extension, after the far end has had a moment to answer.
        if let tones = pendingTones, !tones.isEmpty {
            pendingTones = nil
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.liveCallUUID == uuid else { return }
                self.sendTones(tones)
            }
        }
    }

    // BOREAL_DIALER_v829_RELIABILITY - follows the customer's leg on the server (GET /voice/conferences/:id) while it
    // rings: answered -> connected; busy / no answer / failed -> the reason is shown (BF-Server tells the staff leg and
    // hangs it up; if that does not arrive, the call is ended here).
    private func watchCallee(uuid: UUID) {
        calleeWatch?.cancel()
        calleeWatch = Task { @MainActor [weak self] in
            var endedAt: Date?
            for _ in 0..<180 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, self.isDialing(uuid) else { return }
                await ConferenceSession.shared.refresh()
                guard self.isDialing(uuid) else { return }
                switch ConferenceSession.shared.calleeOutcome {
                case .answered:
                    self.markOutgoingConnected(uuid: uuid)
                    return
                case .unanswered(let reason):
                    if endedAt == nil {
                        endedAt = Date()
                        self.callError = reason
                        Telemetry.event("callee_unanswered", metadata: ["reason": reason], callRef: TwilioVoiceManager.shared.lastCallSid)
                    } else if let since = endedAt, Date().timeIntervalSince(since) > 6 {
                        self.hangUp()
                        return
                    }
                case .ringing:
                    break
                }
            }
            // Three minutes and still not answered (or no word from the server): end it with a reason, never stuck.
            guard let self, self.isDialing(uuid) else { return }
            self.callError = "There was no answer."
            self.hangUp()
        }
    }

    // BOREAL_DIALER_v829_RELIABILITY - why a call could not connect, in words (Twilio error codes).
    func noteConnectFailure(code: Int) {
        // A late failure for a call already ended here (staff hung up while it was calling) is not news.
        guard liveCallUUID != nil else { return }
        callError = VoiceEngine.connectFailureMessage(code: code)
    }

    static func connectFailureMessage(code: Int) -> String {
        switch code {
        case 20101, 20103, 20104, 20107, 20151, 20157:
            return "Your calling session expired. Close and reopen the app, then try again."
        case 31005, 31009, 31530, 53000, 53001, 53405:
            return "The call couldn't connect: the network dropped. Check your signal and try again."
        case 31208, 31401:
            return "The call couldn't use the microphone. Check Settings > Boreal Dialer > Microphone."
        case 31486:
            return "The line is busy."
        case 31480:
            return "There was no answer."
        case 31603:
            return "The call was declined."
        default:
            return "The call couldn't connect (error \(code)). Try again."
        }
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
    // BOREAL_DIALER_v831_DIALER_POLISH - the sheet now names the caller and says how long the call was, and a call
    // that ends while another call's outcome is still unsaved waits its turn instead of replacing it.
    /// `endedEarlier`: the call already finished here (a late Twilio callback), so the details kept at its end apply,
    /// not the call now on screen.
    func publishFinishedCall(callSid: String?, endedEarlier: Bool = false) {
        guard let callSid, !callSid.isEmpty else { return }
        let details: (name: String?, seconds: Int)
        if endedEarlier {
            details = endedDetails ?? (name: nil, seconds: 0)
        } else {
            details = liveCallUUID != nil ? outcomeDetails() : (endedDetails ?? outcomeDetails())
        }
        let call = FinishedCall(callSid: callSid, endedAt: Date(), contactName: details.name, durationSeconds: details.seconds)
        // BOREAL_DIALER_v821 - Calls > Recents offers this call's summary after the outcome sheet is closed.
        AfterCallSummaryStore.shared.record(call)
        if finishedCall?.callSid == callSid || outcomeQueue.contains(where: { $0.callSid == callSid }) { return }
        if finishedCall == nil, outcomeQueue.isEmpty {
            finishedCall = call
        } else {
            outcomeQueue.append(call)
            if finishedCall == nil { finishedCall = outcomeQueue.removeFirst() }
        }
    }

    /// The outcome sheet closed (saved, skipped or swiped away): the next one waiting, unless a call is up.
    func outcomeSheetClosed() {
        finishedCall = nil
        guard !outcomeQueue.isEmpty, !isOnCall else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.finishedCall == nil, !self.isOnCall, !self.outcomeQueue.isEmpty else { return }
            self.finishedCall = self.outcomeQueue.removeFirst()
        }
    }

    /// Sign-out: the next person must not get this person's outcome sheets.
    func clearOutcomes() {
        outcomeQueue.removeAll()
        finishedCall = nil
        endedDetails = nil
    }

    /// Outcome sheets still waiting (tests and diagnostics).
    var waitingOutcomes: [FinishedCall] { outcomeQueue }

    private func beginCallRecord(direction: String) {
        currentDirection = direction
        connectedAt = nil
        callDuration = 0
        endedDetails = nil
    }

    private func outcomeDetails() -> (name: String?, seconds: Int) {
        let number = TwilioVoiceManager.shared.activeNumber ?? currentNumber
        let name = CallerCardStore.shared.card(for: number)?.callKitName ?? (currentHandle.isEmpty ? nil : currentHandle)
        return (name, connectedAt == nil ? 0 : callDuration)
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
        // BOREAL_DIALER_v829_RELIABILITY
        connectWatchdog?.cancel()
        connectWatchdog = nil
        calleeWatch?.cancel()
        calleeWatch = nil
        isConnecting = false
        remoteRinging = false
        answerTappedAt = nil
        // BOREAL_DIALER_v830_DIALER_CONTROLS
        pendingTones = nil
        isReconnecting = false
        isSpeakerOn = false
        sentTones = ""
        state = status
        isMuted = false
        isOnHold = false
        showKeypad = false

        // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - the number and SID come from the
        // Twilio manager; without a number there is nothing to resolve a
        // contact against and the server would reject the event.
        // BOREAL_DIALER_v829_RELIABILITY - a local hang-up clears Twilio's number before this runs, and activeCallSid
        // (the CallKit UUID) is nil once the state is ended: calls staff ended themselves were never logged.
        let number = TwilioVoiceManager.shared.activeNumber ?? currentNumber
        let sid = TwilioVoiceManager.shared.lastCallSid ?? activeCallSid
        // BOREAL_DIALER_v831_DIALER_POLISH - the outcome sheet's name and length, before the call's state is cleared.
        endedDetails = outcomeDetails()
        let seconds = connectedAt == nil ? 0 : callDuration
        let direction = currentDirection
        // An incoming call this phone didn't answer is not this phone's to log: the server knows whether someone else
        // took it, and logging it from every phone that rang put a "call" on the timeline per phone.
        let shouldLog = !(direction == "inbound" && connectedAt == nil)
        connectedAt = nil
        currentNumber = nil
        let key = UUID()
        let statusText = "\(status)"
        Task {
            guard shouldLog else { return }
            // BOREAL_DIALER_OFFLINE_v303 - a call that ends with no signal is logged when it returns.
            // BOREAL_DIALER_v831_DIALER_POLISH - so is one the server couldn't take just then; the same key both times.
            do {
                try await API.logCall(duration: seconds, status: statusText, number: number, callSid: sid,
                                      direction: direction, key: key)
            } catch {
                switch OfflineQueue.classify(error) {
                case .stop, .retry:
                    API.queueCallLog(duration: seconds, status: statusText, number: number, callSid: sid,
                                     direction: direction, key: key)
                case .sent, .refused:
                    break
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
            // BOREAL_DIALER_v831_DIALER_POLISH - an outcome that waited out this call is shown now.
            if self.finishedCall == nil, !self.isOnCall, !self.outcomeQueue.isEmpty {
                self.finishedCall = self.outcomeQueue.removeFirst()
            }
            // BOREAL_DIALER_v817_CALLS - push registration is skipped while a
            // call is up; retry it now so the phone keeps ringing.
            VoiceManager.shared.retryRegistrationAfterCall()
        }
    }

    // BOREAL_DIALER_v831_DIALER_POLISH - the timer stopped while the screen was being scrolled (it ran in the default
    // run-loop mode only) and counted ticks, so it fell behind. It now runs in every mode and reads the clock.
    private func startTimer() {
        callDuration = 0
        let started = Date()
        connectedAt = started
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.connectedAt == started else { return }
                self.callDuration = max(0, Int(Date().timeIntervalSince(started)))
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
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
        answerTappedAt = Date()
        Telemetry.event("answer_tapped", callRef: TwilioVoiceManager.shared.pendingInviteSid)
        // BOREAL_DIALER_v829_RELIABILITY - nothing to answer (the caller hung up, or the ring moved to the cell as the
        // tap landed): fail the action and say so, instead of a "connected" call with no audio.
        guard TwilioVoiceManager.shared.accept() else {
            action.fail()
            callError = "The caller had already hung up, or the call moved to another phone."
            handleFailure()
            return
        }
        // BOREAL_DIALER_v829_RELIABILITY - "Connecting…" until Twilio connects; the timer starts then
        // (handleCallConnected). A call that never connects is ended with a reason, not left silent.
        isConnecting = true
        state = .active(action.callUUID)
        action.fulfill()
        startConnectWatchdog(uuid: action.callUUID)
    }

    // BOREAL_DIALER_v829_RELIABILITY
    private func startConnectWatchdog(uuid: UUID) {
        connectWatchdog?.cancel()
        connectWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: VoiceEngine.connectTimeoutSeconds * 1_000_000_000)
            guard let self, !Task.isCancelled, self.isConnecting, self.liveCallUUID == uuid else { return }
            Telemetry.event("connect_timeout", metadata: ["seconds": "\(VoiceEngine.connectTimeoutSeconds)"],
                            callRef: TwilioVoiceManager.shared.lastCallSid)
            self.callError = "The call couldn't connect. Check your signal and try again."
            self.hangUp()
        }
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
        observeAudioRoute() // BOREAL_DIALER_v830_DIALER_CONTROLS
        // BOREAL_DIALER_v829_RELIABILITY - how long iOS took to hand over the audio after Answer.
        if isConnecting, let tapped = answerTappedAt {
            Telemetry.event("audio_activated", metadata: ["answerToAudioMs": "\(Int(Date().timeIntervalSince(tapped) * 1000))"],
                            callRef: TwilioVoiceManager.shared.lastCallSid)
        }
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
