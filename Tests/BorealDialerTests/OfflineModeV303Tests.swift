import XCTest
@testable import BorealDialer

// BOREAL_DIALER_OFFLINE_v303
final class OfflineModeV303Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        OfflineQueue.shared.clear()
        ResponseCache.clear()
    }

    func testRecognisesNoSignal() {
        XCTAssertTrue(OfflineQueue.isOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(OfflineQueue.isOffline(URLError(.networkConnectionLost)))
        XCTAssertFalse(OfflineQueue.isOffline(URLError(.badServerResponse)))
        XCTAssertFalse(OfflineQueue.isOffline(APIError.serverError))
    }

    func testOutcomesAreKeptInOrder() {
        CallDispositionService.queueOffline(callRef: "CA123", disposition: CallDisposition.allCases[0])
        OfflineQueue.shared.enqueue(label: "Task", path: "/tasks", body: Data("{}".utf8))
        let items = OfflineQueue.shared.load()
        XCTAssertEqual(items.map(\.path), ["/telephony/calls/CA123/disposition", "/tasks"])
        OfflineQueue.shared.clear()
        XCTAssertTrue(OfflineQueue.shared.load().isEmpty)
    }

    func testReadCacheKeepsGetResponsesOnly() throws {
        var get = URLRequest(url: URL(string: "https://server.boreal.financial/api/voice/recent-calls")!)
        get.httpMethod = "GET"
        ResponseCache.store(Data("[1]".utf8), for: get)
        XCTAssertEqual(ResponseCache.load(for: get), Data("[1]".utf8))
        var post = get
        post.httpMethod = "POST"
        XCTAssertNil(ResponseCache.load(for: post))
        ResponseCache.clear()
        XCTAssertNil(ResponseCache.load(for: get))
    }

    func testStatusText() {
        XCTAssertEqual(OfflineStatusBar.text(connected: false, pending: 2), "No signal. 2 changes will send when you're back online.")
        XCTAssertEqual(OfflineStatusBar.text(connected: true, pending: 1), "Sending 1 saved change...")
        XCTAssertNil(OfflineStatusBar.text(connected: true, pending: 0))
    }
}
