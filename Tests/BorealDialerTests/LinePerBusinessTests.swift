// BOREAL_DIALER_LINE_PER_BUSINESS_v1 - every call tells the server which business line it is on.
import XCTest
@testable import BorealDialer

final class LinePerBusinessTests: XCTestCase {
    func testTheChosenLineTravelsWithTheCall() {
        XCTAssertEqual(TwilioVoiceManager.connectParams(dialled: "+14035550100", conferenceFriendly: nil, line: .bi)["silo"], "BI")
        XCTAssertEqual(TwilioVoiceManager.connectParams(dialled: "+14035550100", conferenceFriendly: nil, line: .ks)["silo"], "KS")
        XCTAssertEqual(TwilioVoiceManager.connectParams(dialled: "+14035550100", conferenceFriendly: nil, line: .bf)["silo"], "BF")
    }
    func testNumberAndConferenceAreKept() {
        let p = TwilioVoiceManager.connectParams(dialled: "+14035550100", conferenceFriendly: "conf-1", line: .slf)
        XCTAssertEqual(p["To"], "+14035550100")
        XCTAssertEqual(p["conferenceFriendly"], "conf-1")
        XCTAssertNil(TwilioVoiceManager.connectParams(dialled: "+14035550100", conferenceFriendly: "", line: .bf)["conferenceFriendly"])
    }
}
