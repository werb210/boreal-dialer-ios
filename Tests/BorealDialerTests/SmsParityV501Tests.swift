import XCTest
@testable import BorealDialer

// BOREAL_DIALER_BLOCK_v501_SMS_PARITY
final class SmsParityV501Tests: XCTestCase {
    func testPlainTextSegments() {
        XCTAssertEqual(SmsSegments.count(String(repeating: "a", count: 160)).segments, 1)
        XCTAssertEqual(SmsSegments.count(String(repeating: "a", count: 161)).segments, 2)
        XCTAssertEqual(SmsSegments.count(String(repeating: "a", count: 307)).segments, 3)
    }

    func testUnicodeSegments() {
        XCTAssertTrue(SmsSegments.count("Hi \u{1F44B}").unicode)
        XCTAssertEqual(SmsSegments.count(String(repeating: "\u{2019}", count: 70)).segments, 1)
        XCTAssertEqual(SmsSegments.count(String(repeating: "\u{2019}", count: 71)).segments, 2)
    }

    func testDeliveryTags() {
        XCTAssertEqual(SmsDelivery.tag(status: "delivered", errorCode: nil)?.text, "Delivered")
        XCTAssertTrue(SmsDelivery.tag(status: "undelivered", errorCode: "30034")?.text.contains("not yet registered for US texting") ?? false)
        XCTAssertEqual(SmsDelivery.tag(status: "sent", errorCode: nil)?.text, "Sent")
        XCTAssertNil(SmsDelivery.tag(status: nil, errorCode: nil))
    }

    func testPayloadOmitsMediaWhenAbsent() throws {
        let data = try JSONEncoder().encode(SendSMSPayload(to: "+15875550100", body: "hi", contactId: nil))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("media"))
    }

    func testMessageDecodesDeliveryFields() throws {
        let json = #"{"id":"m1","direction":"outbound","body":"hi","delivery_status":"undelivered","delivery_error":"30034"}"#
        let m = try JSONDecoder().decode(SMSMessage.self, from: Data(json.utf8))
        XCTAssertEqual(m.deliveryStatus, "undelivered")
        XCTAssertEqual(m.deliveryError, "30034")
    }
}
