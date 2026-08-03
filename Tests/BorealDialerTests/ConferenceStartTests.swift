// BOREAL_DIALER_JOIN_CONFERENCE_v46
import XCTest
@testable import BorealDialer

final class ConferenceStartTests: XCTestCase {
    private struct StartResponseMirror: Decodable {
        let ok: Bool
        let conferenceId: String
        let conferenceFriendly: String
        let callerParticipantId: String?
        let calleeParticipantId: String?
    }

    func testPstnStartResponseCarriesTheFriendlyName() throws {
        let json = """
        {"ok":true,"conferenceId":"cf1","conferenceFriendly":"boreal-cf1",
         "callerParticipantId":"p1","calleeParticipantId":"p2","calleeCallSid":"CA1"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StartResponseMirror.self, from: json)
        XCTAssertEqual(decoded.conferenceFriendly, "boreal-cf1")
        XCTAssertEqual(decoded.callerParticipantId, "p1")
    }

    func testMissingFriendlyNameIsADecodeFailure() {
        let json = """
        {"ok":true,"conferenceId":"cf1","callerParticipantId":"p1"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(StartResponseMirror.self, from: json))
    }
}
