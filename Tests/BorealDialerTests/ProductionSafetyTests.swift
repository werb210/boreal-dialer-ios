import XCTest
@testable import BorealDialer

final class ProductionSafetyTests: XCTestCase {
    func testPhoneDeepLinkNormalizesAndDoesNotStartByDefault() {
        XCTAssertEqual(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=+14035551234")!),
                       .phone("+14035551234", start: false))
    }

    func testPhoneDeepLinkSupportsExplicitImmediateStart() {
        XCTAssertEqual(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=+14035551234&start=true")!),
                       .phone("+14035551234", start: true))
    }

    func testContactDeepLinkAndExplicitStart() {
        XCTAssertEqual(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?contactId=abc_123&start=true")!),
                       .contact(id: "abc_123", start: true))
    }

    func testDeepLinkWithoutQueryIsRejected() {
        XCTAssertNil(DialerDeepLinkParser.parse(URL(string: "borealdialer://call")!))
    }

    func testDeepLinkWithDuplicateParameterIsRejected() {
        XCTAssertNil(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=+14035551234&phone=+14035550000")!))
    }

    func testDeepLinkWithUnknownParameterIsRejected() {
        XCTAssertNil(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=+14035551234&unknown=x")!))
    }

    func testDeepLinkWithPhoneAndContactIsRejected() {
        XCTAssertNil(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=+123&contactId=abc")!))
    }

    func testDeepLinkWithInvalidStartIsRejected() {
        XCTAssertNil(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=+14035551234&start=maybe")!))
    }

    func testDeepLinkWithInvalidContactCharactersIsRejected() {
        XCTAssertNil(DialerDeepLinkParser.parse(URL(string: "borealdialer://call?contactId=../../bad")!))
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
        XCTAssertFalse(PushManager.isEligibleVoIPPayload(["type": "general"]))
        XCTAssertFalse(PushManager.isEligibleVoIPPayload([:]))
        XCTAssertTrue(PushManager.isEligibleVoIPPayload([
            "twi_message_type": "twilio.voice.call",
            "twi_call_sid": "CA123"
        ]))
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

    func testDuplicateCallInviteProtection() {
        var ledger = CallInviteLedger()
        XCTAssertTrue(ledger.begin("CA-logical-call"))
        XCTAssertFalse(ledger.begin("CA-logical-call"))
        ledger.finish("CA-logical-call")
        XCTAssertTrue(ledger.begin("CA-logical-call"))
        XCTAssertFalse(ledger.begin(""))
    }

    func testInstalledAppTargetDeclaresSchemeAndSingleProviderOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"))
        XCTAssertTrue(project.contains("borealdialer"))
        let engine = try String(contentsOf: root.appendingPathComponent("Sources/Voice/VoiceEngine.swift"))
        XCTAssertEqual(engine.components(separatedBy: "CXProvider(configuration:").count - 1, 1)
    }

    func testWatchCoreIsIndependentAndTwilioFree() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let watch = root.appendingPathComponent("Watch")
        let sources = try FileManager.default.contentsOfDirectory(at: watch, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0) }.joined(separator: "\n")
        XCTAssertFalse(sources.contains("import TwilioVoice"))
        XCTAssertFalse(sources.contains("WCSession.default.isReachable"))
        XCTAssertFalse(sources.contains("Answers on " + "your phone"))
        XCTAssertTrue(sources.contains("registerForRemoteNotifications"))
        XCTAssertTrue(sources.contains("protocol WatchCallTransport"))
        XCTAssertTrue(sources.contains("URLSession"))
    }

    func testProjectSeparatesPhoneAndIndependentWatchProducts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"))
        XCTAssertTrue(project.contains("TARGETED_DEVICE_FAMILY: \"1\""))
        XCTAssertTrue(project.contains("WKRunsIndependentlyOfCompanionApp: true"))
        let watchTarget = project.components(separatedBy: "BorealDialerWatch:").last ?? ""
        XCTAssertFalse(watchTarget.contains("product: TwilioVoice"))
    }
}
