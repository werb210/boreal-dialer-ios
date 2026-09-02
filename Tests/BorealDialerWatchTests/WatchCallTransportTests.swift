import XCTest
@testable import BorealDialerWatch

final class WatchCallTransportTests: XCTestCase {
    private final class MemoryCredentialStore: WatchCredentialStore {
        var value: String?
        func read() -> String? { value }
        func write(_ token: String) { value = token }
        func clear() { value = nil }
    }

    func testWatchLogoutClearsSessionAndCredentialStore() async throws {
        let credentials = MemoryCredentialStore()
        let auth = WatchAuthService(store: credentials)
        try await auth.establishSession(verifiedToken: "short-lived-test-token")
        XCTAssertNotNil(credentials.value)
        await auth.logout()
        let token = await auth.token
        XCTAssertNil(token)
        XCTAssertNil(credentials.value)
    }

    func testAuthoritativePendingBridgeAndConnectedTransitions() {
        var state = WatchCallStateTracker()
        XCTAssertTrue(state.applyAuthoritative(.requesting))
        XCTAssertTrue(state.applyAuthoritative(.waitingForCallback))
        XCTAssertTrue(state.applyAuthoritative(.bridging))
        XCTAssertTrue(state.applyAuthoritative(.connected))
        XCTAssertEqual(state.status, .connected)
    }

    func testConnectedCannotBeFakedBeforeAuthoritativeProgress() {
        var state = WatchCallStateTracker()
        XCTAssertFalse(state.applyAuthoritative(.connected))
        XCTAssertEqual(state.status, .idle)
        XCTAssertTrue(state.applyAuthoritative(.requesting))
        XCTAssertFalse(state.applyAuthoritative(.connected))
        XCTAssertEqual(state.status, .requesting)
    }

    func testFailedAndEndedStatesAreTerminal() {
        var failed = WatchCallStateTracker()
        XCTAssertTrue(failed.applyAuthoritative(.requesting))
        XCTAssertTrue(failed.applyAuthoritative(.failed))
        XCTAssertFalse(failed.applyAuthoritative(.requesting))

        var ended = WatchCallStateTracker()
        XCTAssertTrue(ended.applyAuthoritative(.requesting))
        XCTAssertTrue(ended.applyAuthoritative(.ended))
        XCTAssertFalse(ended.applyAuthoritative(.connected))
    }

    func testCompanionAndStandaloneSelection() async throws {
        let companion = CompanionWatchCallTransport { _ in .ringing }
        let standalone = ServerBridgeWatchCallTransport { _ in .waitingForCallback }
        let selector = WatchCallTransportSelector(companion: companion, standalone: standalone)

        XCTAssertEqual(selector.mode(companionReachable: true), .companion)
        XCTAssertEqual(selector.mode(companionReachable: false), .standalone)
        let request = CallRequest(destination: "+14035551234", line: .BF)
        let companionStatus = try await selector.transport(companionReachable: true).startCall(request)
        let standaloneStatus = try await selector.transport(companionReachable: false).startCall(request)
        XCTAssertEqual(companionStatus, .ringing)
        XCTAssertEqual(standaloneStatus, .waitingForCallback)
    }

    func testStandaloneNetworkFailureDoesNotBecomeSuccess() async {
        let transport = ServerBridgeWatchCallTransport { _ in throw WatchServiceError.offline }
        do {
            _ = try await transport.startCall(CallRequest(destination: "+14035551234", line: .BF))
            XCTFail("An offline request must not report a call state")
        } catch {
            XCTAssertEqual(error as? WatchServiceError, .offline)
        }
    }

    func testRecentCallWireContractRoundTrips() throws {
        XCTAssertEqual(WatchCallDirection.incoming.rawValue, "incoming")
        XCTAssertEqual(WatchCallDirection.outgoing.rawValue, "outgoing")
        XCTAssertEqual(WatchCallDirection.missed.rawValue, "missed")

        let call = WatchRecentCall(
            id: "call-1",
            name: "Test Contact",
            number: "+14035551234",
            direction: .incoming,
            occurredAt: Date(timeIntervalSince1970: 1_788_291_200),
            line: .BF
        )
        let encoded = try JSONEncoder().encode(call)
        let decoded = try JSONDecoder().decode(WatchRecentCall.self, from: encoded)
        XCTAssertEqual(decoded, call)
        requireSendable(call)
    }

    private func requireSendable<T: Sendable>(_ value: T) {}

    func testInvalidDestinationNeverStartsOperation() async {
        let transport = ServerBridgeWatchCallTransport { _ in XCTFail(); return .waitingForCallback }
        do { _ = try await transport.startCall(CallRequest(destination: "123", line: .BF)); XCTFail() }
        catch { XCTAssertEqual(error as? WatchServiceError, .invalidDestination) }
    }

    func testMissingServerCapabilityDoesNotClaimCallStarted() async {
        let transport = ServerBridgeWatchCallTransport()
        do { _ = try await transport.startCall(CallRequest(destination: "+14035551234", line: .BF)); XCTFail() }
        catch { XCTAssertEqual(error as? WatchServiceError, .serverCapabilityUnavailable) }
    }

    func testLineIsCapturedAtCreation() async throws {
        let transport = ServerBridgeWatchCallTransport { request in
            XCTAssertEqual(request.line, .SLF); XCTAssertEqual(request.destination, "+14035551234")
            return .waitingForCallback
        }
        let status = try await transport.startCall(CallRequest(destination: "403 555 1234", line: .SLF))
        XCTAssertEqual(status, .waitingForCallback)
    }

    func testDuplicateTapIsRejectedWhileFirstRequestWaits() async {
        let transport = ServerBridgeWatchCallTransport { _ in
            try await Task.sleep(nanoseconds: 100_000_000); return .waitingForCallback
        }
        async let first = transport.startCall(CallRequest(destination: "+14035551234", line: .BF))
        try? await Task.sleep(nanoseconds: 10_000_000)
        do { _ = try await transport.startCall(CallRequest(destination: "+14035551234", line: .BI)); XCTFail() }
        catch { XCTAssertEqual(error as? WatchServiceError, .duplicateRequest) }
        _ = try? await first
    }

    func testCancelDuringSetupPreventsSuccess() async {
        let transport = ServerBridgeWatchCallTransport { _ in
            try await Task.sleep(nanoseconds: 100_000_000); return .waitingForCallback
        }
        let task = Task { try await transport.startCall(CallRequest(destination: "+14035551234", line: .BF)) }
        try? await Task.sleep(nanoseconds: 10_000_000); await transport.cancelSetup()
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertEqual(error as? WatchServiceError, .cancelled) }
    }

    func testWatchNotificationRoutingRejectsExecutableOrMalformedIdentifiers() {
        guard case .message(let valid) = WatchNotificationRouter.route(
            userInfo: ["type": "client_message", "id": "message_123"]
        ) else { return XCTFail("Expected a message route") }
        XCTAssertEqual(valid, "message_123")

        guard case .call(let unsafe) = WatchNotificationRouter.route(
            userInfo: ["type": "call", "id": "https://evil.example/call"]
        ) else { return XCTFail("Expected a typed call route") }
        XCTAssertNil(unsafe)
        guard case .home = WatchNotificationRouter.route(
            userInfo: ["type": "unknown", "id": "123"]
        ) else { return XCTFail("Unknown notification types must be inert") }
    }
}
