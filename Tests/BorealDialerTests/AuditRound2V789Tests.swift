// BOREAL_DIALER_V789_AUDIT - keychain lock handling, team chat parity, SMS
// typing, Maya chats, notifications, config and logging.
import Foundation
import Security
import XCTest
@testable import BorealDialer

final class AuditRound2V789Tests: XCTestCase {

    // [179] keychain

    func testLockedKeychainIsNotSignedOut() {
        XCTAssertEqual(KeychainService.readResult(status: errSecInteractionNotAllowed, value: nil), .locked)
        XCTAssertEqual(KeychainService.readResult(status: errSecItemNotFound, value: nil), .notFound)
        let data = Data("t".utf8)
        XCTAssertEqual(KeychainService.readResult(status: errSecSuccess, value: data as AnyObject), .found(data))
        XCTAssertEqual(KeychainService.readResult(status: errSecParam, value: nil), .failed(errSecParam))
    }

    func testItemsAreReadableAfterFirstUnlockOnThisDeviceOnly() {
        XCTAssertEqual(KeychainService.accessibility as String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    // [183] team chat parity

    func testTeamMessageDecodesReactionsAsListOrMap() throws {
        let list = #"{"id":"m1","channel_id":"c1","sender_id":"a","body":"hi","edited_at":"2026-10-01T10:00:00Z","pinned":true,"reactions":[{"emoji":"\u2705","user_ids":["a","b"]}]}"#
        let m = try JSONDecoder().decode(TeamMessage.self, from: Data(list.utf8))
        XCTAssertEqual(m.reactions?.first?.emoji, "\u{2705}")
        XCTAssertEqual(m.reactions?.first?.count, 2)
        XCTAssertEqual(m.pinned, true)
        XCTAssertNotNil(m.edited_at)

        let map = #"{"id":"m2","channel_id":"c1","body":"hi","reactions":{"\ud83d\udc4d":["a"]}}"#
        let m2 = try JSONDecoder().decode(TeamMessage.self, from: Data(map.utf8))
        XCTAssertEqual(m2.reactions, [TeamReaction(emoji: "\u{1F44D}", count: 1, user_ids: ["a"])])
    }

    func testTeamMessageToleratesNullBodyAndOddReactions() throws {
        let json = #"{"id":7,"channel_id":"c1","body":null,"deleted_at":"2026-10-01T10:00:00Z","reactions":"weird","read_by":"nope"}"#
        let m = try JSONDecoder().decode(TeamMessage.self, from: Data(json.utf8))
        XCTAssertEqual(m.id, "7")
        XCTAssertEqual(m.body, "")
        XCTAssertNotNil(m.deleted_at)
        XCTAssertNil(m.read_by)
        XCTAssertTrue((m.reactions ?? []).isEmpty)
    }

    func testOneBadMessageDoesNotEmptyTheList() {
        let json = #"{"messages":[{"id":"m1","body":"ok"},{"body":"no id"},{"id":"m3","body":"ok"}]}"#
        let messages = TeamLossy.list(TeamMessage.self, from: Data(json.utf8), keys: ["messages"])
        XCTAssertEqual(messages.map(\.id), ["m1", "m3"])
    }

    func testTypingIsThrottledToThreeSeconds() {
        let t0 = Date()
        XCTAssertTrue(TeamParityStore.shouldSendTyping(lastSent: nil, now: t0))
        XCTAssertFalse(TeamParityStore.shouldSendTyping(lastSent: t0, now: t0.addingTimeInterval(2.9)))
        XCTAssertTrue(TeamParityStore.shouldSendTyping(lastSent: t0, now: t0.addingTimeInterval(3)))
    }

    func testTypersExcludeMeAndLapse() {
        let now = Date()
        let seen = ["me": now, "ann": now.addingTimeInterval(-1), "bob": now.addingTimeInterval(-30)]
        XCTAssertEqual(TeamParityStore.activeTypers(seen, now: now, excluding: "me"), ["ann"])
    }

    func testSeenByUsesReadTimeOrMessageIdAndSkipsTheSender() {
        let json = #"{"id":"m1","channel_id":"c1","sender_id":"me","body":"x","created_at":"2026-10-01T10:00:00Z"}"#
        guard let message = try? JSONDecoder().decode(TeamMessage.self, from: Data(json.utf8)) else { return XCTFail() }
        let reads = [
            TeamChannelRead(user_id: "me", read_at: "2026-10-01T11:00:00Z", message_id: nil),
            TeamChannelRead(user_id: "ann", read_at: "2026-10-01T10:05:00.123Z", message_id: nil),
            TeamChannelRead(user_id: "bob", read_at: "2026-10-01T09:00:00Z", message_id: nil),
            TeamChannelRead(user_id: "cy", read_at: nil, message_id: "m1"),
        ]
        XCTAssertEqual(TeamParityStore.seenBy(message, reads: reads).map(\.user_id), ["ann", "cy"])
    }

    func testReadsDecodeCamelOrSnake() {
        let json = #"{"reads":[{"userId":"a","lastReadAt":null,"last_read_at":"2026-10-01T10:00:00Z"},{"user_id":"b"}]}"#
        let reads = TeamLossy.list(TeamChannelRead.self, from: Data(json.utf8), keys: ["reads"])
        XCTAssertEqual(reads.map(\.user_id), ["a", "b"])
        XCTAssertEqual(reads.first?.read_at, "2026-10-01T10:00:00Z")
    }

    func testEndpointPathsEncodeIdsAndEmoji() {
        XCTAssertEqual(TeamParityStore.messagePath(channelId: "c1", messageId: "m/1"), "/team/channels/c1/messages/m%2F1")
        XCTAssertEqual(TeamParityStore.queryValue("\u{1F44D}"), "%F0%9F%91%8D")
        XCTAssertEqual(TeamParityStore.queryValue("a&b=c"), "a%26b%3Dc")
        XCTAssertNotNil(URL(string: APIConfig.BASE_URL + TeamParityStore.messagePath(channelId: "c1", messageId: "m1")
                            + "/reactions?emoji=" + TeamParityStore.queryValue("\u{2764}\u{FE0F}")))
    }

    // [184] SMS typing, Maya, notifications

    func testSmsTypingThrottleAndPollPath() {
        let t0 = Date()
        XCTAssertTrue(SMSTypingMonitor.shouldSend(lastSent: nil, now: t0))
        XCTAssertFalse(SMSTypingMonitor.shouldSend(lastSent: t0, now: t0.addingTimeInterval(1.4)))
        XCTAssertTrue(SMSTypingMonitor.shouldSend(lastSent: t0, now: t0.addingTimeInterval(1.5)))
        XCTAssertEqual(SMSTypingMonitor.typingPath(contactId: "abc"), "/communications/messages/typing?contactId=abc&side=client")
        XCTAssertEqual(SMSTypingMonitor.pollInterval, 3)
    }

    func testSmsTypingResponseShapes() {
        XCTAssertTrue(SMSTypingMonitor.isTyping(Data(#"{"typing":true}"#.utf8)))
        XCTAssertTrue(SMSTypingMonitor.isTyping(Data(#"{"data":{"isTyping":true}}"#.utf8)))
        XCTAssertTrue(SMSTypingMonitor.isTyping(Data(#"{"typing":[{"contactId":"x"}]}"#.utf8)))
        XCTAssertFalse(SMSTypingMonitor.isTyping(Data(#"{"typing":false}"#.utf8)))
        XCTAssertFalse(SMSTypingMonitor.isTyping(Data(#"{}"#.utf8)))
        XCTAssertFalse(SMSTypingMonitor.isTyping(Data("not json".utf8)))
    }

    func testMayaSessionsAndMessagesDecodeTolerantly() {
        let sessions = #"{"sessions":[{"id":"s1","contact_name":"Ann","status":"active"},{"sessionId":42},{"nope":true}]}"#
        let decoded = TeamLossy.list(MayaSession.self, from: Data(sessions.utf8), keys: ["sessions"])
        XCTAssertEqual(decoded.map(\.id), ["s1", "42"])
        XCTAssertEqual(decoded.first?.title, "Ann")
        XCTAssertEqual(decoded.last?.title, "Website visitor")

        let messages = #"[{"id":"1","role":"assistant","content":"Hi, I am Maya"},{"sender":"user","text":"Hello"}]"#
        let thread = TeamLossy.list(MayaMessage.self, from: Data(messages.utf8), keys: ["messages"])
        XCTAssertEqual(thread.count, 2)
        XCTAssertTrue(thread[0].fromMaya)
        XCTAssertFalse(thread[1].fromMaya)
        XCTAssertEqual(thread[1].body, "Hello")
        XCTAssertEqual(MayaSessionsViewModel.messagesPath(sessionId: "s1"), "/communications/maya-sessions/s1/messages")
    }

    func testNotificationReadPath() {
        XCTAssertEqual(NotificationsViewModel.pathSegment("n 1"), "n%201")
    }

    // [186] [189] config and logging

    func testTeamSocketIsDerivedFromTheBFBaseURL() {
        XCTAssertEqual(APIConfig.TEAM_WS_URL, "wss://server.boreal.financial/api/team/ws")
        XCTAssertEqual(APIConfig.webSocketURL(fromHTTPBase: "http://localhost:3000/api"), "ws://localhost:3000/api")
    }

    func testLoggedURLsNeverCarryQueryStrings() {
        let url = URL(string: "https://server.boreal.financial/api/communications/sms/thread?phone=%2B14165550123#x")
        XCTAssertEqual(APIClient.loggableURL(url), "https://server.boreal.financial/api/communications/sms/thread")
        XCTAssertEqual(APIClient.loggableURL(nil), "")
    }

    // [182] sign-out clears the shared surfaces

    func testSharedSurfacesClear() {
        WidgetSnapshotStore.save([WidgetContact(name: "Ann", number: "+14165550123")])
        WidgetSnapshotStore.clear()
        XCTAssertTrue(WidgetSnapshotStore.load().contacts.isEmpty)

        DialerDashboardStore.save(DialerDashboard(missed: [], callsToday: 3, tasks: [], updatedAt: Date()))
        DialerDashboardStore.clear()
        XCTAssertEqual(DialerDashboardStore.load(), .empty)

        WatchSnapshotSync.publish(WatchSnapshot(status: "busy", missedCalls: 2, tasksDue: 1))
        WatchSnapshotSync.clear()
        XCTAssertEqual(WatchSnapshotSync.lastPublished(), WatchSnapshot(status: "away", missedCalls: 0, tasksDue: 0))

        CallDirectoryStore.clear()
        XCTAssertTrue(CallDirectoryStore.entries().isEmpty)
    }
}
