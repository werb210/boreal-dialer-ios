// BOREAL_DIALER_v871_CALL_QUEUES - a call-queue offer (BF-Server v871) rings from Boreal's own number with the waiting
// caller in the invite's parameters; missed-call alerts and Call back must use the caller's number.
import XCTest
@testable import BorealDialer

final class CallQueueV871Tests: XCTestCase {
    func testQueueOfferUsesTheWaitingCallersNumber() {
        let params = ["queueCall": "c1", "queueName": "Sales", "callerName": "Pat", "callerCompany": "Sales%20queue%20call", "callerNumber": "%2B14035550111"]
        XCTAssertEqual(CallerCard.handleForInvite(from: "+18665550100", parameters: params), "+14035550111")
        XCTAssertEqual(CallerCard.fromInviteParameters(params)?.callKitName, "Pat · Sales queue call")
    }

    func testEveryOtherCallKeepsItsOwnNumber() {
        XCTAssertEqual(CallerCard.handleForInvite(from: "+14035550199", parameters: ["callerName": "Tanya", "callerNumber": "+1999"]), "+14035550199")
        XCTAssertEqual(CallerCard.handleForInvite(from: "+14035550199", parameters: nil), "+14035550199")
        XCTAssertEqual(CallerCard.handleForInvite(from: "+18665550100", parameters: ["queueCall": "c1", "callerNumber": " "]), "+18665550100")
    }
}
