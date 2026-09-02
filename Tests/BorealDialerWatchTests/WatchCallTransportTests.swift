import XCTest
@testable import BorealDialerWatch

final class WatchCallTransportTests: XCTestCase {
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
}
