// BOREAL_DIALER_v820_WATCH
// One call flow for every place the Watch starts a call (keypad, contact, voice, favorites, recents, calls due):
//   - iPhone reachable  -> ask the iPhone app to place an ordinary VoIP/CallKit call (audio on AirPods / iPhone / Watch,
//                          no cellular minutes);
//   - iPhone not reachable, or it vanished mid-request -> BF-Server's callback bridge (POST /telephony/watch/calls), which
//                          rings the staff cell (and so this Watch); answer and press 1.
// The bridge's status is polled while the call is being set up, so the screen moves through
// requesting -> ringing your Watch -> connected -> ended instead of stopping at the first answer.
import Foundation
import SwiftUI
import WatchKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// BOREAL_DIALER_v820_WATCH - the WCSession half of the iPhone path. Not actor-isolated: WCSession is thread-safe and
/// the reply arrives on a background queue.
enum WatchCompanionLink {
    static var isReachable: Bool {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isReachable
#else
        return false
#endif
    }

    /// Resolves to `.ringing` once the iPhone has started the call. Throws `.companionUnavailable` when the message could
    /// not be delivered (the caller falls back to the server bridge) and `.companionRefused` when the iPhone said no.
    static func requestCall(_ request: CallRequest) async throws -> WatchCallStatus {
#if canImport(WatchConnectivity)
        guard isReachable else { throw WatchServiceError.companionUnavailable }
        let payload = WatchPayload.encode(WatchPhoneCallRequest(destination: request.destination, contactId: request.contactId),
                                          under: WatchPayload.phoneCallKey)
        guard !payload.isEmpty else { throw WatchServiceError.invalidResponse }
        let reply: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            // WCSession calls exactly one of the two handlers (the error handler also covers a timeout).
            WCSession.default.sendMessage(payload, replyHandler: { message in
                continuation.resume(returning: message)
            }, errorHandler: { _ in
                continuation.resume(throwing: WatchServiceError.companionUnavailable)
            })
        }
        guard let decoded = WatchPayload.decode(WatchPhoneCallReply.self, from: reply, key: WatchPayload.phoneCallReplyKey) else {
            // An iPhone app older than v820 answers with an empty reply: treat it as unreachable and use the bridge.
            throw WatchServiceError.companionUnavailable
        }
        guard decoded.accepted else { throw WatchServiceError.companionRefused(reason: decoded.reason ?? "") }
        return .ringing
#else
        throw WatchServiceError.companionUnavailable
#endif
    }

    /// A notification Reply the Watch cannot send itself. Delivered now when the iPhone is reachable, otherwise queued.
    static func sendReply(_ message: WatchAlertReplyMessage) {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload = WatchPayload.encode(message, under: WatchPayload.alertReplyKey)
        guard !payload.isEmpty else { return }
        if WatchCompanionLink.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
#endif
    }
}

/// BOREAL_DIALER_v820_WATCH - Reply on a notification shown on the Watch. Texts go straight to Boreal from the Watch
/// (POST /watch/sms, works without the iPhone); portal messages need the staff session, so the iPhone sends them.
enum WatchAlertReplies {
    @MainActor
    static func send(_ text: String, userInfo: [AnyHashable: Any]) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let payload = BorealAlertPayload(userInfo: userInfo) else { return }
        let relay = WatchAlertReplyMessage(kind: payload.kind.rawValue, contactId: payload.contactId,
                                           phone: payload.phone, threadKind: payload.threadKind, body: body)
        if case .sms(let phone, _)? = BorealAlertReplyTarget.target(for: payload) {
            do {
                try await DirectWatchSMSService().send(to: phone, body: body)
                WKInterfaceDevice.current().play(.success)
                return
            } catch {
                // Not linked or offline: let the iPhone try.
            }
        }
        WatchCompanionLink.sendReply(relay)
    }
}

@MainActor
final class WatchCallController: ObservableObject {
    @Published private(set) var status: WatchCallStatus = .idle
    @Published private(set) var path: WatchCallPath?
    @Published private(set) var errorMessage: String?
    private var bridge: ServerBridgeWatchCallTransport?
    private var pollTask: Task<Void, Never>?

    /// True from the request until the call is connected, ended or failed.
    var isSettingUp: Bool { [.requesting, .waitingForCallback, .bridging, .ringing].contains(status) }

    var statusText: String { WatchCallPath.statusText(status, path: path) }

    func start(_ request: CallRequest) {
        guard !isSettingUp else { return }
        pollTask?.cancel()
        errorMessage = nil
        status = .requesting
        let chosen = WatchCallPath.choose(companionReachable: WatchCompanionLink.isReachable)
        path = chosen
        WKInterfaceDevice.current().play(.start)
        Task { @MainActor in
            if chosen == .viaIPhone {
                do {
                    let companion = CompanionWatchCallTransport { request in try await WatchCompanionLink.requestCall(request) }
                    let placed = try await companion.startCall(request)
                    self.status = placed
                    WKInterfaceDevice.current().play(.success)
                    return
                } catch WatchServiceError.companionUnavailable {
                    // The iPhone went out of reach between the check and the send: use the server bridge instead.
                    self.path = .serverCallback
                } catch let error as WatchServiceError {
                    self.fail(error.safeMessage)
                    return
                } catch {
                    self.fail("Call request failed")
                    return
                }
            }
            await self.startBridge(request)
        }
    }

    /// Cancels a bridge call that is still being set up. A connected carrier call is hung up in the Watch's Phone app.
    func cancel() {
        pollTask?.cancel()
        if let bridge { Task { await bridge.cancelSetup() } }
        status = .ended
    }

    private func startBridge(_ request: CallRequest) async {
        let transport = ServerBridgeWatchCallTransport()
        bridge = transport
        do {
            let first = try await transport.startCall(request)
            status = first
            poll(transport, from: first)
        } catch let error as WatchServiceError {
            fail(error.safeMessage)
        } catch {
            fail("Call request failed")
        }
    }

    private func poll(_ transport: ServerBridgeWatchCallTransport, from first: WatchCallStatus) {
        pollTask = Task { @MainActor in
            var tracker = WatchCallStateTracker()
            _ = tracker.applyAuthoritative(.requesting)
            _ = tracker.applyAuthoritative(first)
            // About three minutes: long enough to answer the callback and for the client to pick up.
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                guard let next = try? await transport.refreshStatus() else { continue }
                if tracker.applyAuthoritative(next) {
                    self.status = next
                    if next == .connected { WKInterfaceDevice.current().play(.success) }
                    if next == .failed { WKInterfaceDevice.current().play(.failure) }
                }
                if [.connected, .ended, .failed].contains(next) { return }
            }
        }
    }

    private func fail(_ message: String) {
        status = .failed
        errorMessage = message
        WKInterfaceDevice.current().play(.failure)
    }
}

/// BOREAL_DIALER_v820_WATCH - status block shown under every Watch call button.
struct WatchCallStatusView: View {
    @ObservedObject var controller: WatchCallController

    var body: some View {
        if controller.status != .idle {
            VStack(alignment: .leading, spacing: 2) {
                if let path = controller.path {
                    Label(path.banner, systemImage: path == .viaIPhone ? "iphone" : "applewatch")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchTheme.greenBright)
                }
                Text(controller.statusText)
                    .font(.caption2)
                    .foregroundStyle(controller.status == .failed ? Color.red : Color.secondary)
                if let message = controller.errorMessage {
                    Text(message).font(.caption2).foregroundStyle(.red)
                }
                if controller.isSettingUp && controller.path == .serverCallback {
                    Button("Cancel", role: .destructive) { controller.cancel() }
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
