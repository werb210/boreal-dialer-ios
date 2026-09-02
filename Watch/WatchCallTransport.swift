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
    private(set) var version: Int = -1

    mutating func applyAuthoritative(_ next: WatchCallStatus) -> Bool {
        guard !Self.terminal.contains(status), Self.allowed[status, default: []].contains(next) else {
            return false
        }
        status = next
        return true
    }

    mutating func applyAuthoritative(_ next: WatchCallStatus, version nextVersion: Int) -> Bool {
        guard nextVersion > version, applyAuthoritative(next) else { return false }
        version = nextVersion; return true
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

actor ServerBridgeWatchCallTransport: WatchCallTransport {
    typealias StartOperation = @Sendable (CallRequest) async throws -> WatchCallStatus
    private let startOperation: StartOperation?
    private let client: WatchAPIClient?
    private var isRequesting = false
    private var cancelled = false
    private var activeCallId: String?
    private var lastVersion = -1
    init(startOperation: StartOperation? = nil, client: WatchAPIClient? = nil) {
        self.startOperation = startOperation
        self.client = client ?? (startOperation == nil ? try? WatchAPIClient() : nil)
    }
    func startCall(_ request: CallRequest) async throws -> WatchCallStatus {
        guard !isRequesting else { throw WatchServiceError.duplicateRequest }
        guard PhoneNumberNormalizer.normalize(request.destination) != nil else {
            throw WatchServiceError.invalidDestination
        }
        isRequesting = true; cancelled = false
        defer { isRequesting = false }
        let normalized = CallRequest(destination: PhoneNumberNormalizer.normalize(request.destination)!, line: request.line, contactId: request.contactId)
        let status: WatchCallStatus
        if let startOperation { status = try await startOperation(normalized) }
        else {
            guard let client else { throw WatchServiceError.invalidResponse }
            let key = UUID().uuidString
            struct Body: Encodable { let destination: String; let line: BorealLine; let contactId: String? }
            struct Response: Decodable { let callId: String; let status: WatchCallStatus; let version: Int; let updatedAt: String? }
            let body = try JSONEncoder().encode(Body(destination: normalized.destination, line: normalized.line, contactId: normalized.contactId))
            let data: Data
            do { data = try await client.request(path: "/telephony/watch/calls", method: "POST", body: body, line: normalized.line, headers: ["Idempotency-Key":key]) }
            catch WatchServiceError.offline { data = try await client.request(path: "/telephony/watch/calls", method: "POST", body: body, line: normalized.line, headers: ["Idempotency-Key":key]) }
            let response = try JSONDecoder().decode(Response.self, from: data)
            activeCallId = response.callId; lastVersion = response.version; status = response.status
        }
        if cancelled { throw WatchServiceError.cancelled }
        return status
    }
    func cancelSetup() async { cancelled = true; isRequesting = false; try? await end() }
    func end() async throws {
        guard let callId = activeCallId, let client else { return }
        _ = try await client.request(path: "/telephony/watch/calls/\(callId)", method: "DELETE")
        activeCallId = nil
    }
    /// One bounded, foreground refresh. Callers schedule this only while setup is active.
    func refreshStatus() async throws -> WatchCallStatus? {
        guard let callId = activeCallId, let client else { return nil }
        struct Response: Decodable { let callId: String; let status: WatchCallStatus; let version: Int }
        let data = try await client.request(path: "/telephony/watch/calls/\(callId)")
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.version > lastVersion else { return nil }
        lastVersion = response.version
        if [.connected, .ended, .failed].contains(response.status) { activeCallId = nil }
        return response.status
    }
    func mute() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func unmute() async throws { throw WatchServiceError.serverCapabilityUnavailable }
    func sendDTMF(_ digits: String) async throws { throw WatchServiceError.serverCapabilityUnavailable }
}
