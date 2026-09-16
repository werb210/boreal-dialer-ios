import XCTest
@testable import BorealDialer

// BOREAL_DIALER_BACKGROUND_SEND_v309
final class BackgroundSendV309Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        OfflineQueue.shared.clear()
    }

    func testOutcomes() {
        XCTAssertEqual(BackgroundSender.outcome(for: 200), .sent)
        XCTAssertEqual(BackgroundSender.outcome(for: 404), .refused)
        XCTAssertEqual(BackgroundSender.outcome(for: 401), .retry)
        XCTAssertEqual(BackgroundSender.outcome(for: 0), .retry)
        XCTAssertEqual(BackgroundSender.outcome(for: 503), .retry)
    }

    func testQueuedItemsFromBeforeThisVersionStillDecode() throws {
        let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","label":"Task","path":"/tasks","method":"POST","silo":"BF","createdAt":0,"attempts":0}]"#
        let decoded = try JSONDecoder().decode([QueuedRequest].self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.first?.handedAt)
    }

    func testNothingIsHandedOffWithoutASession() {
        OfflineQueue.shared.enqueue(label: "Task", path: "/tasks", body: Data("{}".utf8))
        TokenStorage.shared.clear()
        OfflineQueue.shared.handOffToBackground()
        XCTAssertNil(OfflineQueue.shared.load().first?.handedAt)
    }
}
