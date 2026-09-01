import XCTest
@testable import BorealDialer

final class ProductionSafetyTests: XCTestCase {
    func testPhoneDeepLinkNormalizesAndDoesNotStartByDefault() {
        XCTAssertEqual(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=%2B14165550123")!),
                       .phone("+14165550123", start: false))
    }

    func testContactDeepLinkAndExplicitStart() {
        XCTAssertEqual(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?contactId=abc_123&start=true")!),
                       .contact(id: "abc_123", start: true))
    }

    func testMalformedAndUntrustedDeepLinksAreRejected() {
        ["javascript:alert(1)", "file:///tmp/x", "borealdialer://call?phone=555-1212",
         "borealdialer://call?phone=%2B14165550123&evil=x",
         "borealdialer://call?phone=%2B14165550123&contactId=x"].forEach {
            XCTAssertNil(DialerDeepLinkParser.parse(URL(string: $0)!))
        }
    }

    func testOrdinaryNotificationRoutes() {
        XCTAssertEqual(AppNotificationRouter.route(userInfo: ["type": "client_message", "applicationId": "1"]),
                       .clientMessage(applicationId: "1"))
        XCTAssertEqual(AppNotificationRouter.route(userInfo: ["type": "stage_change", "applicationId": "2"]),
                       .stageChange(applicationId: "2"))
    }

    @MainActor
    func testVoIPPathRejectsGeneralNotificationTypes() {
        XCTAssertFalse(PushManager.isEligibleVoIPPayload(["type": "client_message"]))
        XCTAssertFalse(PushManager.isEligibleVoIPPayload(["type": "stage_change"]))
    }

    func testTwilioInviteUUIDIsLogicalCallUUID() {
        let inviteUUID = UUID()
        let state = VoiceEngine.State.ringing(inviteUUID)
        guard case .ringing(let stateUUID) = state else { return XCTFail() }
        XCTAssertEqual(inviteUUID, stateUUID)
        XCTAssertEqual(inviteUUID.uuidString, WatchEvent(kind: .incomingCall,
                                                          callId: stateUUID.uuidString,
                                                          displayName: "", handle: "").callId)
    }

    func testInstalledAppTargetDeclaresSchemeAndSingleProviderOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"))
        XCTAssertTrue(project.contains("borealdialer"))
        let engine = try String(contentsOf: root.appendingPathComponent("Sources/Voice/VoiceEngine.swift"))
        XCTAssertEqual(engine.components(separatedBy: "CXProvider(configuration:").count - 1, 1)
    }
}
