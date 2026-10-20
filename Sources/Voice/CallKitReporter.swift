// BOREAL_DIALER_CALLKIT_REPORTER_v789
// The one path from a VoIP push to CallKit.
//
// iOS 13+ terminates an app that receives a PushKit VoIP push and does not
// report a call to CallKit, and after a few strikes stops delivering VoIP
// pushes to it at all. Before v789 three paths broke that rule:
//   - an unrecognised payload was dropped (PushManager),
//   - a duplicate invite, or an invite while another call was up, was rejected
//     without reporting anything (TwilioVoiceManager, VoiceEngine.reportIncoming
//     and the 1.5 s "ended" cooldown in VoiceEngine.finishCall),
//   - the report itself was made after a DispatchQueue.main.async hop, and the
//     PushKit completion was called before CallKit had answered.
//
// Every push now reports a call synchronously on the PushKit queue. A push that
// cannot ring reports a placeholder call and ends it at once (.failed for an
// unrecognised payload, .unanswered for busy or duplicate), rejecting the
// Twilio invite. The PushKit completion runs only after CallKit's
// reportNewIncomingCall callback.
import Foundation
import CallKit

/// The CallKit calls the reporter makes. CXProvider in the app, a fake in tests.
protocol CallKitProviding: AnyObject {
    func reportIncoming(uuid: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void)
    func reportEnded(uuid: UUID, at date: Date, reason: CXCallEndedReason)
    func reportUpdated(uuid: UUID, update: CXCallUpdate)
}

/// The parts of a Twilio CallInvite the reporter needs. CallInvite has no
/// public initialiser, so tests supply their own conforming type.
protocol IncomingCallInvite: AnyObject {
    var callSid: String { get }
    var uuid: UUID { get }
    var from: String? { get }
    func reject()
}

final class CXProviderReporting: CallKitProviding {
    let provider: CXProvider

    init(provider: CXProvider) {
        self.provider = provider
    }

    func reportIncoming(uuid: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void) {
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            completion(error)
        }
    }

    func reportEnded(uuid: UUID, at date: Date, reason: CXCallEndedReason) {
        provider.reportCall(with: uuid, endedAt: date, reason: reason)
    }

    func reportUpdated(uuid: UUID, update: CXCallUpdate) {
        provider.reportCall(with: uuid, updated: update)
    }
}

@MainActor
final class CallKitReporter {

    enum InviteDecision: Equatable {
        case ring
        case rejectDuplicate
        case rejectBusy
        case rejectSignedOut // BOREAL_DIALER_v832_SIGNOUT_ALERTS
    }

    static let shared = CallKitReporter()

    /// Set by VoiceEngine when it creates the app's only CXProvider.
    var provider: CallKitProviding?
    /// True while a call is ringing, connecting, connected, or in the short
    /// ended/failed cooldown after one.
    var isLineBusy: @MainActor () -> Bool
    /// Hands an eligible payload to the Twilio SDK. Twilio calls its
    /// NotificationDelegate synchronously on this (main) queue.
    var handleTwilioPayload: @MainActor ([AnyHashable: Any]) -> Bool
    /// BOREAL_DIALER_v832_SIGNOUT_ALERTS - nobody is signed in on this phone. A sign-out done with no signal could not
    /// tell Twilio to stop sending calls here, so the phone kept ringing for an app nobody was signed in to. Those calls
    /// are now turned away at once (the caller moves on to the rest of the ring or voicemail). A keychain that is only
    /// locked (just restarted, not yet unlocked) is not "signed out".
    var isSignedOut: @MainActor () -> Bool

    /// Creates the app's CXProvider (VoiceEngine) if it does not exist yet.
    var ensureProvider: @MainActor () -> Void = { _ = VoiceEngine.shared }

    /// The PushKit delivery being handled right now, if any.
    private var currentPush: PushDelivery?

    init(provider: CallKitProviding? = nil,
         isLineBusy: (@MainActor () -> Bool)? = nil,
         handleTwilioPayload: (@MainActor ([AnyHashable: Any]) -> Bool)? = nil,
         isSignedOut: (@MainActor () -> Bool)? = nil) {
        self.provider = provider
        // An injected provider (tests) starts signed in unless told otherwise.
        if let isSignedOut {
            self.isSignedOut = isSignedOut
        } else if provider == nil {
            self.isSignedOut = { PendingSignOut.isDefinitelySignedOut() }
        } else {
            self.isSignedOut = { false }
        }
        self.isLineBusy = isLineBusy ?? {
            // BOREAL_DIALER_v831_DIALER_POLISH - isOnCall, not !isIdle: the 1.5 s pause after a call turned callers away.
            CallStateManager.shared.current() != .idle || VoiceEngine.shared.isOnCall
        }
        self.handleTwilioPayload = handleTwilioPayload ?? { payload in
            PushManager.shared.handlePushPayload(payload)
        }
    }

    nonisolated static func decide(isDuplicate: Bool, isBusy: Bool, isSignedOut: Bool = false) -> InviteDecision {
        if isDuplicate { return .rejectDuplicate }
        if isSignedOut { return .rejectSignedOut } // BOREAL_DIALER_v832_SIGNOUT_ALERTS
        if isBusy { return .rejectBusy }
        return .ring
    }

    // MARK: - PushKit entry

    /// Called synchronously from pushRegistry(_:didReceiveIncomingPushWith:...).
    /// `completion` is the PushKit completion; it runs exactly once, after
    /// CallKit has answered the report this push produced.
    func handleVoIPPush(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        // VoiceEngine owns the CXProvider and installs it here when created.
        // A push on a cold launch must never find it missing.
        if provider == nil { ensureProvider() }
        let push = PushDelivery(completion: completion)
        currentPush = push
        if PushManager.isEligibleVoIPPayload(payload) {
            _ = handleTwilioPayload(payload)
        }
        currentPush = nil

        // Unrecognised, refused by Twilio, or accepted by Twilio without an
        // invite (a cancel): iOS still requires a reported call.
        if !push.claimed {
            push.claimed = true
            reportPlaceholder(handle: nil, reason: .failed, push: push)
        }
    }

    // MARK: - Invites

    /// TwilioVoiceManager's NotificationDelegate hands every invite here.
    /// `ring` starts the real incoming call; it is only called for `.ring`.
    @discardableResult
    func receive(invite: IncomingCallInvite, firstDelivery: Bool,
                 ring: (IncomingCallInvite) -> Void) -> InviteDecision {
        let decision = Self.decide(isDuplicate: !firstDelivery, isBusy: isLineBusy(), isSignedOut: isSignedOut())
        switch decision {
        case .ring:
            ring(invite)
        case .rejectDuplicate:
            // BOREAL_DIALER_v830_DIALER_CONTROLS - a second delivery of the push for the call that is ringing: account
            // for it, but never reject the invite - that is the same call, and rejecting it sent the caller to
            // voicemail while the phone kept ringing.
            reportPlaceholder(handle: invite.from, reason: .unanswered, push: claimPush())
        case .rejectBusy, .rejectSignedOut:
            invite.reject()
            reportPlaceholder(handle: invite.from, reason: .unanswered, push: claimPush())
        }
        // Whatever ring() did, this push is accounted for: the real report (or
        // its own placeholder) owns the completion from here.
        if let push = currentPush, !push.claimed {
            push.claimed = true
            reportPlaceholder(handle: invite.from, reason: .failed, push: push)
        }
        return decision
    }

    /// Reports a real ringing call. `onResult` receives true when CallKit
    /// accepted it; on false the caller must reject the invite and reset.
    func reportRinging(uuid: UUID, handle: String, update: CXCallUpdate,
                       onResult: @escaping (Bool) -> Void) {
        let push = claimPush()
        guard let provider else {
            onResult(false)
            push?.finish()
            return
        }
        provider.reportIncoming(uuid: uuid, update: update) { error in
            let accepted = error == nil
            Self.onMain {
                onResult(accepted)
                push?.finish()
            }
        }
    }

    /// A call that cannot ring: report it (iOS requires it), then end it at once.
    /// A fresh UUID is used so a duplicate never ends the call that is ringing.
    func reportPlaceholder(handle: String?, reason: CXCallEndedReason) {
        reportPlaceholder(handle: handle, reason: reason, push: claimPush())
    }

    private func reportPlaceholder(handle: String?, reason: CXCallEndedReason, push: PushDelivery?) {
        guard let provider else {
            push?.finish()
            return
        }
        let uuid = UUID()
        let update = CXCallUpdate()
        let value = (handle?.isEmpty == false ? handle : nil) ?? "Boreal"
        update.remoteHandle = CXHandle(type: .generic, value: value)
        update.localizedCallerName = value
        update.hasVideo = false
        provider.reportIncoming(uuid: uuid, update: update) { [weak provider] _ in
            provider?.reportEnded(uuid: uuid, at: Date(), reason: reason)
            push?.finish()
        }
    }

    func reportEnded(uuid: UUID, reason: CXCallEndedReason) {
        provider?.reportEnded(uuid: uuid, at: Date(), reason: reason)
    }

    func reportUpdated(uuid: UUID, update: CXCallUpdate) {
        provider?.reportUpdated(uuid: uuid, update: update)
    }

    // MARK: - Helpers

    /// The current push's completion, taken by the first report it produces.
    private func claimPush() -> PushDelivery? {
        guard let push = currentPush, !push.claimed else { return nil }
        push.claimed = true
        return push
    }

    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }
}

/// One PushKit delivery. The completion is called at most once.
final class PushDelivery {
    private var completion: (() -> Void)?
    var claimed = false

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func finish() {
        let callback = completion
        completion = nil
        callback?()
    }
}
