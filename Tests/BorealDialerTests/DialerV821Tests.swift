// BOREAL_DIALER_v821 - after-call summary, caller card, voicemail alert routing, quick replies, call hours, Focus filter
// and the Siri briefings: the pure logic behind each.
import XCTest
import UserNotifications
@testable import BorealDialer

final class AfterCallSummaryV821Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testDecodesTheBareContractShape() throws {
        let json = Data(#"{"status":"ready","summary":"Walter sends statements Friday.","nextSteps":["Collect statements"," "],"taskId":"t1","contactId":"c1","contactName":"Walter White"}"#.utf8)
        let result = try AfterCallSummaryService.decode(json)
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.summary, "Walter sends statements Friday.")
        XCTAssertEqual(result.nextSteps, ["Collect statements"])
        XCTAssertTrue(result.taskCreated)
        XCTAssertEqual(result.contactId, "c1")
        XCTAssertEqual(result.contactName, "Walter White")
    }

    func testAcceptsAnEnvelopeAndMissingFields() throws {
        let json = Data(#"{"data":{"status":"pending"}}"#.utf8)
        let result = try AfterCallSummaryService.decode(json)
        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.nextSteps, [])
        XCTAssertFalse(result.taskCreated)
        XCTAssertEqual(try AfterCallSummaryService.decode(Data(#"{"status":"none"}"#.utf8)).status, .noSummary)
    }

    func testPollsEveryFiveSecondsForTwoMinutes() {
        XCTAssertEqual(AfterCallSummaryPoller.interval, 5)
        XCTAssertEqual(AfterCallSummaryPoller.limit, 120)
        let poller = AfterCallSummaryPoller(startedAt: start)
        XCTAssertTrue(poller.shouldPoll(now: start))
        XCTAssertTrue(poller.shouldPoll(now: start.addingTimeInterval(115)))
        XCTAssertFalse(poller.shouldPoll(now: start.addingTimeInterval(120)))
    }

    func testPendingKeepsWaitingAndReadyStops() {
        var poller = AfterCallSummaryPoller(startedAt: start)
        poller.apply(AfterCallSummary(status: .pending), now: start.addingTimeInterval(5))
        XCTAssertEqual(poller.phase, .waiting)
        poller.apply(nil, now: start.addingTimeInterval(10)) // a failed request is transient
        XCTAssertEqual(poller.phase, .waiting)
        let ready = AfterCallSummary(status: .ready, summary: "S", nextSteps: ["Call back Friday"])
        poller.apply(ready, now: start.addingTimeInterval(15))
        XCTAssertEqual(poller.phase, .ready(ready))
        XCTAssertFalse(poller.shouldPoll(now: start.addingTimeInterval(20)))
        // Once finished, later answers change nothing.
        poller.apply(AfterCallSummary(status: .noSummary), now: start.addingTimeInterval(25))
        XCTAssertEqual(poller.phase, .ready(ready))
    }

    func testNoneAndEmptyReadyAreUnavailable() {
        var none = AfterCallSummaryPoller(startedAt: start)
        none.apply(AfterCallSummary(status: .noSummary), now: start)
        XCTAssertEqual(none.phase, .unavailable)
        var empty = AfterCallSummaryPoller(startedAt: start)
        empty.apply(AfterCallSummary(status: .ready), now: start)
        XCTAssertEqual(empty.phase, .unavailable)
    }

    func testTimesOutAfterTwoMinutes() {
        var poller = AfterCallSummaryPoller(startedAt: start)
        poller.apply(AfterCallSummary(status: .pending), now: start.addingTimeInterval(121))
        XCTAssertEqual(poller.phase, .timedOut)
        var quiet = AfterCallSummaryPoller(startedAt: start)
        quiet.expireIfNeeded(now: start.addingTimeInterval(60))
        XCTAssertEqual(quiet.phase, .waiting)
        quiet.expireIfNeeded(now: start.addingTimeInterval(130))
        XCTAssertEqual(quiet.phase, .timedOut)
    }

    func testPathUsesTheCallSidAndRefusesAnythingElse() {
        XCTAssertEqual(AfterCallSummaryService.path(callSid: " CA0123456789abcdef0123456789abcdef "),
                       "/calls/CA0123456789abcdef0123456789abcdef/summary")
        XCTAssertNil(AfterCallSummaryService.path(callSid: "../admin"))
        XCTAssertNil(AfterCallSummaryService.path(callSid: ""))
    }

    func testRecentsBannerLastsHalfAnHourAndCanBeDismissed() {
        let call = FinishedCall(callSid: "CA1", endedAt: start)
        XCTAssertEqual(AfterCallSummaryStore.bannerCall(latest: call, dismissed: nil, now: start.addingTimeInterval(60)), call)
        XCTAssertNil(AfterCallSummaryStore.bannerCall(latest: call, dismissed: "CA1", now: start.addingTimeInterval(60)))
        XCTAssertNil(AfterCallSummaryStore.bannerCall(latest: call, dismissed: nil, now: start.addingTimeInterval(31 * 60)))
        XCTAssertNil(AfterCallSummaryStore.bannerCall(latest: nil, dismissed: nil, now: start))
    }
}

final class CallerCardV821Tests: XCTestCase {
    func testInviteParametersBecomeACard() throws {
        let card = try XCTUnwrap(CallerCard.fromInviteParameters([
            "callerName": " Tanya Voss ", "callerCompany": "Voss Trucking", "callerStage": "Underwriting", "contactId": "c_42"
        ]))
        XCTAssertTrue(card.found)
        XCTAssertEqual(card.name, "Tanya Voss")
        XCTAssertEqual(card.company, "Voss Trucking")
        XCTAssertEqual(card.stage, "Underwriting")
        XCTAssertEqual(card.contactId, "c_42")
        XCTAssertNil(card.lastNote)
        XCTAssertEqual(card.callKitName, "Tanya Voss · Voss Trucking")
        XCTAssertTrue(card.isDisplayable)
    }

    func testNoCallerNameMeansNoCard() {
        XCTAssertNil(CallerCard.fromInviteParameters(nil))
        XCTAssertNil(CallerCard.fromInviteParameters([:]))
        XCTAssertNil(CallerCard.fromInviteParameters(["callerName": "  ", "callerStage": "Lead"]))
    }

    func testEncodedParametersAreDecodedButPlainOnesAreLeftAlone() throws {
        XCTAssertEqual(CallerCard.decodedParameter("Tanya%20Voss"), "Tanya Voss")
        XCTAssertEqual(CallerCard.decodedParameter("Tanya+Voss%2C+CFO"), "Tanya Voss, CFO")
        XCTAssertEqual(CallerCard.decodedParameter("A+ Lending"), "A+ Lending")
        let card = try XCTUnwrap(CallerCard.fromInviteParameters(["callerName": "Tanya", "contactId": "../x"]))
        XCTAssertNil(card.contactId, "an unsafe id must not reach navigation or a request path")
        XCTAssertEqual(card.callKitName, "Tanya")
    }

    func testDecodesTheCallerCardEndpoint() throws {
        let json = Data(#"{"found":true,"contactId":"c1","name":"Walter","company":"Gray Matter","stage":"Funded","applicationId":"a1","lastNote":"Wants a second LOC","lastContactAt":"2026-10-16T15:00:00Z","tags":["VIP",""]}"#.utf8)
        let card = try CallerCardService.decode(json)
        XCTAssertEqual(card.stage, "Funded")
        XCTAssertEqual(card.lastNote, "Wants a second LOC")
        XCTAssertEqual(card.applicationId, "a1")
        XCTAssertEqual(card.tags, ["VIP"])
        let missing = try CallerCardService.decode(Data(#"{"found":false}"#.utf8))
        XCTAssertFalse(missing.isDisplayable)
        XCTAssertNil(missing.callKitName)
    }

    func testCallerCardPathEncodesThePlus() {
        XCTAssertEqual(CallerCardService.path(phone: "+14035550100"), "/voice/caller-card?phone=%2B14035550100")
        XCTAssertEqual(CallerCardService.path(phone: "(403) 555-0100"), "/voice/caller-card?phone=%2B14035550100")
        XCTAssertNil(CallerCardService.path(phone: "client:staff-1"))
    }

    func testStoreMatchesTheSameNumberInAnyFormat() {
        XCTAssertEqual(CallerCardStore.digits("+1 (403) 555-0100"), CallerCardStore.digits("4035550100"))
    }
}

final class VoicemailAlertV821Tests: XCTestCase {
    func testVoicemailIdOpensThatVoicemail() throws {
        let payload = try XCTUnwrap(BorealAlertPayload(userInfo: [
            "type": "voicemail", "voicemailId": "vm_123", "phone": "+14035550100"
        ]))
        XCTAssertEqual(payload.voicemailId, "vm_123")
        XCTAssertEqual(AlertDestination.destination(for: payload), .voicemailMessage(id: "vm_123"))
        XCTAssertEqual(AlertDestination.voicemailMessage(id: "vm_123").tab, .calls)
    }

    func testWithoutAUsableIdItOpensTheVoicemailList() {
        XCTAssertEqual(AlertDestination.destination(userInfo: ["type": "voicemail"]), .voicemail)
        XCTAssertEqual(AlertDestination.destination(userInfo: ["type": "voicemail", "voicemailId": "../../x"]), .voicemail)
    }

    func testOnlyVoicemailAlertsKeepTheId() {
        let sms = BorealAlertPayload(userInfo: ["type": "sms", "phone": "+14035550100", "voicemailId": "vm_1"])
        XCTAssertNil(sms?.voicemailId)
    }
}

final class QuickRepliesV821Tests: XCTestCase {
    func testSnippetsFirstServerOrderKeptEmptiesAndDuplicatesDropped() {
        let items = [
            QuickReply(id: "t1", name: "Docs", body: "Please send your statements.", isSnippet: false),
            QuickReply(id: "s1", name: "On my way", body: "Calling you in 5.", isSnippet: true),
            QuickReply(id: "t2", name: "Empty", body: "  ", isSnippet: false),
            QuickReply(id: "s2", name: "Thanks", body: "Thanks {{first_name}}!", isSnippet: true),
            QuickReply(id: "s1", name: "Dup", body: "dup", isSnippet: true),
        ]
        XCTAssertEqual(QuickReplyOrdering.ordered(items).map(\.id), ["s1", "s2", "t1"])
    }

    func testDecodesTheContractAndOlderShapes() throws {
        let contract = Data(#"{"items":[{"id":"1","name":"Hi","body":"Hello","isSnippet":true},{"name":"no id"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(QuickReplyEnvelope.self, from: contract).items
        XCTAssertEqual(decoded, [QuickReply(id: "1", name: "Hi", body: "Hello", isSnippet: true)])
        let legacy = Data(#"{"templates":[{"id":7,"name":"","body_text":"Call me back","is_snippet":false}]}"#.utf8)
        let old = try JSONDecoder().decode(QuickReplyEnvelope.self, from: legacy).items
        XCTAssertEqual(old, [QuickReply(id: "7", name: "Call me back", body: "Call me back", isSnippet: false)])
        XCTAssertEqual(QuickReplyOrdering.path(), "/templates/quick?channel=sms")
    }

    func testCacheIsFreshForADay() throws {
        let suite = "v821.quickreplies.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = QuickReplyCache(defaults: defaults)
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertNil(cache.load(now: now))
        cache.store([QuickReply(id: "t", name: "T", body: "B", isSnippet: false),
                     QuickReply(id: "s", name: "S", body: "B", isSnippet: true)], at: now)
        let fresh = try XCTUnwrap(cache.load(now: now.addingTimeInterval(3600)))
        XCTAssertTrue(fresh.fresh)
        XCTAssertEqual(fresh.items.map(\.id), ["s", "t"])
        XCTAssertFalse(try XCTUnwrap(cache.load(now: now.addingTimeInterval(25 * 3600))).fresh)
        cache.clear()
        XCTAssertNil(cache.load(now: now))
    }
}

final class CallHoursV821Tests: XCTestCase {
    func testTimesParseAndFormat() {
        XCTAssertEqual(CallHoursDraft.parse("08:00"), 480)
        XCTAssertEqual(CallHoursDraft.parse("8:30"), 510)
        XCTAssertEqual(CallHoursDraft.parse("24:00"), 1440)
        XCTAssertNil(CallHoursDraft.parse("25:00"))
        XCTAssertNil(CallHoursDraft.parse("08:60"))
        XCTAssertNil(CallHoursDraft.parse("8am"))
        XCTAssertEqual(CallHoursDraft.format(480), "08:00")
        XCTAssertEqual(CallHoursDraft.format(1439), "23:59")
    }

    func testWeekdaysAndWeekendOffIsTheSimpleLayout() {
        let hours = CallHours(enabled: true, timezone: "America/Edmonton", weekly: [
            "mon": [["08:00", "18:00"]], "tue": [["08:00", "18:00"]], "wed": [["08:00", "18:00"]],
            "thu": [["08:00", "18:00"]], "fri": [["08:00", "18:00"]], "sat": [], "sun": []
        ], urgentPassthrough: true)
        let draft = CallHoursDraft(hours, deviceTimeZone: "America/Toronto")
        XCTAssertFalse(draft.customPerDay)
        XCTAssertFalse(draft.weekendOn)
        XCTAssertEqual(draft.timezone, "America/Edmonton")
        XCTAssertEqual(draft.toCallHours(), hours)
        XCTAssertEqual(draft.validationErrors(), [])
    }

    func testDifferentDaysOpenThePerDayLayoutAndExtraRangesSurvive() {
        let hours = CallHours(enabled: true, timezone: "", weekly: [
            "mon": [["08:00", "12:00"], ["13:00", "17:00"]], "fri": [["09:00", "15:00"]]
        ], urgentPassthrough: false)
        let draft = CallHoursDraft(hours, deviceTimeZone: "America/Edmonton")
        XCTAssertTrue(draft.customPerDay)
        XCTAssertEqual(draft.timezone, "America/Edmonton", "an empty zone falls back to the device's")
        let body = draft.toCallHours()
        XCTAssertEqual(body.weekly["mon"], [["08:00", "12:00"], ["13:00", "17:00"]])
        XCTAssertEqual(body.weekly["fri"], [["09:00", "15:00"]])
        XCTAssertEqual(body.weekly["tue"], [])
        XCTAssertEqual(body.weekly.count, 7, "every day is sent, a day off as []")
    }

    func testSimpleLayoutWithWeekendsOnCopiesTheHours() {
        var draft = CallHoursDraft.defaults(timezone: "America/Edmonton")
        draft.weekdayHours.start = 9 * 60
        draft.weekdayHours.end = 17 * 60 + 30
        draft.weekendOn = true
        let body = draft.toCallHours()
        XCTAssertEqual(body.weekly["sat"], [["09:00", "17:30"]])
        XCTAssertEqual(body.weekly["mon"], [["09:00", "17:30"]])
    }

    func testValidation() {
        var draft = CallHoursDraft.defaults(timezone: "Not/AZone")
        draft.weekdayHours.start = 18 * 60
        draft.weekdayHours.end = 8 * 60
        let errors = draft.validationErrors()
        XCTAssertTrue(errors.contains("Pick a time zone."))
        XCTAssertTrue(errors.contains("Monday: the end time must be after the start time."))

        var allOff = CallHoursDraft.defaults(timezone: "America/Edmonton")
        allOff.enabled = true
        allOff.customPerDay = true
        for day in CallHoursDay.allCases { allOff.days[day] = .off }
        XCTAssertEqual(allOff.validationErrors(), ["Turn on at least one day, or turn off Call hours."])
    }

    func testBodyUsesTheContractKeys() throws {
        let body = CallHoursDraft.defaults(timezone: "America/Edmonton").toCallHours()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: CallHoursService.encode(body)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["enabled", "timezone", "weekly", "urgentPassthrough"])
        let decoded = try CallHoursService.decode(CallHoursService.encode(body))
        XCTAssertEqual(decoded, body)
    }
}

final class FocusFilterV821Tests: XCTestCase {
    func testClientAlertsAndInternalAlerts() {
        for type in ["missed_call", "voicemail", "sms", "client_message", "handoff"] {
            XCTAssertEqual(FocusAlertPolicy.audience(userInfo: ["type": type]), .client, type)
        }
        XCTAssertEqual(FocusAlertPolicy.audience(userInfo: ["aps": ["category": "SMS"]]), .client)
        XCTAssertEqual(FocusAlertPolicy.audience(userInfo: ["type": "team_mention"]), .internalStaff)
        XCTAssertEqual(FocusAlertPolicy.audience(userInfo: [:]), .internalStaff)
        // The server's filter-criteria wins.
        XCTAssertEqual(FocusAlertPolicy.audience(userInfo: ["type": "sms", "aps": ["filter-criteria": "internal"]]),
                       .internalStaff)
    }

    func testClientOnlyHoldsBackInternalAlerts() {
        XCTAssertTrue(FocusAlertPolicy.shouldPresent(.internalStaff, mode: .all))
        XCTAssertTrue(FocusAlertPolicy.shouldPresent(.client, mode: .clientOnly))
        XCTAssertFalse(FocusAlertPolicy.shouldPresent(.internalStaff, mode: .clientOnly))
        XCTAssertEqual(FocusAlertPolicy.presentationOptions(userInfo: ["type": "team_mention"], mode: .clientOnly), [])
        XCTAssertEqual(FocusAlertPolicy.presentationOptions(userInfo: ["type": "voicemail"], mode: .clientOnly),
                       [.banner, .list, .sound])
    }

    func testSystemPredicateHidesOnlyInternal() throws {
        XCTAssertNil(FocusAlertPolicy.notificationPredicate(for: .all))
        let predicate = try XCTUnwrap(FocusAlertPolicy.notificationPredicate(for: .clientOnly))
        XCTAssertTrue(predicate.evaluate(with: "client"))
        XCTAssertFalse(predicate.evaluate(with: "internal"))
    }

    func testModeIsRememberedAndDefaultsToAll() throws {
        let suite = "v821.focus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FocusAlertPolicy.load(defaults), .all)
        FocusAlertPolicy.store(.clientOnly, in: defaults)
        XCTAssertEqual(FocusAlertPolicy.load(defaults), .clientOnly)
    }

    func testLocalAlertsAreTagged() throws {
        let missed = try XCTUnwrap(MissedCallNotification.content(handle: "+14035550100"))
        XCTAssertEqual(missed.filterCriteria, "client")
        XCTAssertEqual(missed.interruptionLevel, .timeSensitive)
        let team = UNMutableNotificationContent()
        FocusAlertPolicy.tag(team, as: .internalStaff)
        XCTAssertEqual(team.filterCriteria, "internal")
        XCTAssertEqual(team.interruptionLevel, .active)
    }

    func testTheEntitlementIsDeclared() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let entitlements = try String(contentsOf: dir.appendingPathComponent("Config/BorealDialer.entitlements"), encoding: .utf8)
        XCTAssertTrue(entitlements.contains("com.apple.developer.usernotifications.time-sensitive"))
        let spec = try String(contentsOf: dir.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(spec.contains("com.apple.developer.usernotifications.time-sensitive: true"))
    }
}

final class SiriBriefingV821Tests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    func testFollowUpCallsWithAReason() {
        let action = StaffBriefing.followUpAction(NextFollowUp(found: true, taskId: "t1", title: "bank statements",
                                                               contactId: "c1", contactName: "Tanya Voss",
                                                               phone: "403-555-0100"))
        XCTAssertEqual(action, .call(phone: "+14035550100", dialog: "Calling Tanya Voss about bank statements."))
    }

    func testFollowUpExplainsWhenItCannotCall() {
        XCTAssertEqual(StaffBriefing.followUpAction(NextFollowUp(found: false)),
                       .explain("You have no follow-ups due in Boreal."))
        XCTAssertEqual(StaffBriefing.followUpAction(NextFollowUp(found: true, contactName: "Tanya Voss")),
                       .explain("Your next follow-up is Tanya Voss, but there's no phone number on file."))
    }

    func testDecodesTheMissedSummary() throws {
        let json = Data(#"{"missedCalls":[{"name":"Tanya","phone":"+14035550100","at":"2026-10-17T15:05:00Z"}],"unreadMessages":[{"name":"Walter","contactId":"c1","preview":"Sent the docs","at":"2026-10-17T15:00:00.000Z","kind":"sms"}],"voicemails":[]}"#.utf8)
        let summary = try JSONDecoder().decode(MissedSummary.self, from: json)
        XCTAssertEqual(summary.missedCalls.count, 1)
        XCTAssertEqual(summary.unreadMessages.first?.preview, "Sent the docs")
        XCTAssertNotNil(StaffBriefing.parseDate("2026-10-17T15:00:00.000Z"))
        XCTAssertEqual(try JSONDecoder().decode(MissedSummary.self, from: Data("{}".utf8)), MissedSummary())
    }

    func testReadsMessagesAndCountsTheRest() {
        XCTAssertEqual(StaffBriefing.messagesDialog(MissedSummary()), "You have no unread client messages.")
        let messages = (1...5).map {
            MissedSummary.UnreadMessage(name: "Client \($0)", contactId: "c\($0)", preview: "Hello \($0)", at: nil, kind: "sms")
        }
        let text = StaffBriefing.messagesDialog(MissedSummary(unreadMessages: messages))
        XCTAssertTrue(text.hasPrefix("You have 5 unread client messages."))
        XCTAssertTrue(text.contains("Client 1 said: Hello 1"))
        XCTAssertFalse(text.contains("Client 4 said"))
        XCTAssertTrue(text.hasSuffix("And 2 more in Boreal Dialer."))
    }

    func testSaysWhoCalled() {
        let now = Date(timeIntervalSince1970: 1_792_249_200) // 2026-10-17 15:00 UTC
        let today = MissedSummary.MissedCall(name: "Tanya Voss", phone: "+14035550100", at: "2026-10-17T14:05:00Z")
        let yesterday = MissedSummary.MissedCall(name: nil, phone: "+14035550101", at: "2026-10-16T14:05:00Z")
        let text = StaffBriefing.callersDialog(MissedSummary(missedCalls: [today, yesterday]), now: now, calendar: utc,
                                               locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertTrue(text.hasPrefix("You missed 2 calls."))
        XCTAssertTrue(text.contains("Tanya Voss, at "))
        XCTAssertTrue(text.contains("(403) 555-0101, yesterday at "))
        XCTAssertEqual(StaffBriefing.callersDialog(MissedSummary()), "No missed calls.")
        let onlyVoicemail = MissedSummary(voicemails: [.init(name: "Walter", phone: nil, at: nil, excerpt: "Call me")])
        XCTAssertEqual(StaffBriefing.callersDialog(onlyVoicemail), "No missed calls, but Walter left a voicemail.")
    }
}
