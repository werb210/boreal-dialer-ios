import Foundation

protocol WatchCallTransport {
    func startCall(_ request: CallRequest) async throws -> WatchCallStatus
    func cancelSetup() async
    func end() async throws
    func mute() async throws
    func unmute() async throws
    func sendDTMF(_ digits: String) async throws
}

/// Applies only server/companion-confirmed states. In particular, elapsed time
/// can never manufacture a connected call on the Watch.
struct WatchCallStateTracker {
    private(set) var status: WatchCallStatus = .idle

    mutating func applyAuthoritative(_ next: WatchCallStatus) -> Bool {
        guard !Self.terminal.contains(status), Self.allowed[status, default: []].contains(next) else {
            return false
        }
        status = next
        return true
    }

    private static let terminal: Set<WatchCallStatus> = [.ended, .failed]
    private static let allowed: [WatchCallStatus: Set<WatchCallStatus>] = [
        .idle: [.requesting],
        .requesting: [.waitingForCallback, .bridging, .ringing, .failed, .ended],
        .waitingForCallback: [.bridging, .ringing, .failed, .ended],
        .bridging: [.ringing, .connected, .failed, .ended],
        .ringing: [.bridging, .connected, .failed, .ended],
        .connected: [.ended, .failed]
    ]
}

/// Selects the fastest available transport without making WatchConnectivity a
/// prerequisite. A nearby, reachable phone is an optimization only.
struct WatchCallTransportSelector {
    let companion: any WatchCallTransport
    let standalone: any WatchCallTransport

    func mode(companionReachable: Bool) -> WatchOperatingMode {
        companionReachable ? .companion : .standalone
    }

    func transport(companionReachable: Bool) -> any WatchCallTransport {
        companionReachable ? companion : standalone
    }
}

/// Companion operations are injected by the connectivity boundary, keeping
/// WCSession out of the UI and allowing a failed handoff to be represented as
/// a failure rather than synthetic call success.
actor CompanionWatchCallTransport: WatchCallTransport {
    typealias StartOperation = @Sendable (CallRequest) async throws -> WatchCallStatus
    private let startOperation: StartOperation
    init(startOperation: @escaping StartOperation) { self.startOperation = startOperation }
    func startCall(_ request: CallRequest) async throws -> WatchCallStatus {
        guard PhoneNumberNormalizer.normalize(request.destination) != nil else {
            throw WatchServiceError.invalidDestination
        }
        return try await startOperation(request)
    }
    func cancelSetup() async {}
    func end() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func mute() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func unmute() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func sendDTMF(_ digits: String) async throws { throw WatchServiceError.serverCapabilityUnavailable }
}

/// Server bridge boundary. No endpoint is guessed: until the server advertises
/// and configures this capability, a call request fails visibly and safely.
actor ServerBridgeWatchCallTransport: WatchCallTransport {
    typealias StartOperation = @Sendable (CallRequest) async throws -> WatchCallStatus
    private let startOperation: StartOperation?
    private var isRequesting = false
    private var cancelled = false
    init(startOperation: StartOperation? = nil) { self.startOperation = startOperation }
    func startCall(_ request: CallRequest) async throws -> WatchCallStatus {
        guard !isRequesting else { throw WatchServiceError.duplicateRequest }
        guard PhoneNumberNormalizer.normalize(request.destination) != nil else {
            throw WatchServiceError.invalidDestination
        }
        isRequesting = true; cancelled = false
        defer { isRequesting = false }
        guard let startOperation else { throw WatchServiceError.serverCapabilityUnavailable }
        let status = try await startOperation(CallRequest(destination: PhoneNumberNormalizer.normalize(request.destination)!,
                                                          line: request.line, contactId: request.contactId))
        if cancelled { throw WatchServiceError.cancelled }
        return status
    }
    func cancelSetup() { cancelled = true; isRequesting = false }
    func end() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func mute() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func unmute() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func sendDTMF(_ digits: String) async throws { throw WatchServiceError.serverCapabilityUnavailable }
}
