// BOREAL_DIALER_v821 - after-call summary: BF-Server writes an AI summary, next steps and (when it can) a follow-up task
// once Twilio finishes the transcript. GET /calls/{callSid}/summary answers
// {status: "pending"|"ready"|"none", summary?, nextSteps?: [string], taskId?, contactId?, contactName?}.
// The call-ended sheet and Calls > Recents poll it every 5 s for up to 2 minutes while it is "pending".
import Foundation

/// BOREAL_DIALER_v821 - the decoded GET /calls/{callSid}/summary body.
struct AfterCallSummary: Decodable, Equatable, Sendable {
    enum Status: String, Sendable {
        // Not `none`: a case named none is ambiguous with Optional.none wherever a Status? is compared.
        case pending, ready, noSummary = "none"
    }

    let statusRaw: String
    let summary: String?
    let nextSteps: [String]
    let taskId: String?
    let contactId: String?
    let contactName: String?

    init(status: Status, summary: String? = nil, nextSteps: [String] = [], taskId: String? = nil,
         contactId: String? = nil, contactName: String? = nil) {
        self.statusRaw = status.rawValue
        self.summary = summary
        self.nextSteps = nextSteps
        self.taskId = taskId
        self.contactId = contactId
        self.contactName = contactName
    }

    private enum CodingKeys: String, CodingKey {
        case status, summary, nextSteps, taskId, contactId, contactName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusRaw = (try c.decodeIfPresent(String.self, forKey: .status) ?? "pending").lowercased()
        summary = Self.clean(try? c.decodeIfPresent(String.self, forKey: .summary))
        // A malformed list must not throw away a good summary.
        let steps = (try? c.decodeIfPresent([String].self, forKey: .nextSteps)) ?? []
        nextSteps = steps.compactMap { Self.clean($0) }
        taskId = Self.clean(try? c.decodeIfPresent(String.self, forKey: .taskId))
        contactId = Self.clean(try? c.decodeIfPresent(String.self, forKey: .contactId))
        contactName = Self.clean(try? c.decodeIfPresent(String.self, forKey: .contactName))
    }

    /// An unknown status from a newer server reads as "pending" so the poller keeps asking until its time limit.
    var status: Status { Status(rawValue: statusRaw) ?? .pending }

    var taskCreated: Bool { taskId != nil }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// BOREAL_DIALER_v821 - pure polling rules, so the 5 s / 2 min behaviour is unit-tested without a network.
struct AfterCallSummaryPoller: Equatable {
    enum Phase: Equatable {
        /// Still waiting on the transcript (or on the first answer).
        case waiting
        /// The summary arrived.
        case ready(AfterCallSummary)
        /// The server says there will be no summary for this call.
        case unavailable
        /// Two minutes passed with no summary. It still lands on the contact timeline.
        case timedOut
    }

    static let interval: TimeInterval = 5
    static let limit: TimeInterval = 120
    static var intervalNanoseconds: UInt64 { UInt64(interval * 1_000_000_000) }

    let startedAt: Date
    private(set) var phase: Phase = .waiting

    init(startedAt: Date) { self.startedAt = startedAt }

    var isFinished: Bool { phase != .waiting }

    /// Whether another request should be made at `now`.
    func shouldPoll(now: Date) -> Bool {
        phase == .waiting && now.timeIntervalSince(startedAt) < Self.limit
    }

    /// Applies one answer. `nil` is a failed request: keep waiting (transient) unless the time is up.
    mutating func apply(_ result: AfterCallSummary?, now: Date) {
        guard phase == .waiting else { return }
        if let result {
            switch result.status {
            case .ready:
                // "ready" with nothing to show is the same as no summary.
                if result.summary != nil || !result.nextSteps.isEmpty {
                    phase = .ready(result)
                } else {
                    phase = .unavailable
                }
                return
            case .noSummary:
                phase = .unavailable
                return
            case .pending:
                break
            }
        }
        if now.timeIntervalSince(startedAt) >= Self.limit { phase = .timedOut }
    }

    /// Called when the loop stops without an answer (time limit reached between polls).
    mutating func expireIfNeeded(now: Date) {
        if phase == .waiting, now.timeIntervalSince(startedAt) >= Self.limit { phase = .timedOut }
    }
}

/// BOREAL_DIALER_v821 - GET /calls/{callSid}/summary.
enum AfterCallSummaryService {
    /// A CallSid is "CA" + 32 hex characters; anything else that is path-safe is passed through (the server also accepts
    /// its own call ids), and anything that is not is refused rather than escaped into the path.
    static func pathSegment(_ callSid: String) -> String? {
        let trimmed = callSid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128,
              trimmed.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return trimmed
    }

    static func path(callSid: String) -> String? {
        pathSegment(callSid).map { "/calls/\($0)/summary" }
    }

    /// The contract is a bare object; an { data: {...} } envelope (the older /calls/summary shape) is accepted too.
    static func decode(_ data: Data) throws -> AfterCallSummary {
        struct Envelope: Decodable { let data: AfterCallSummary? }
        if let enveloped = try? JSONDecoder().decode(Envelope.self, from: data), let inner = enveloped.data {
            return inner
        }
        return try JSONDecoder().decode(AfterCallSummary.self, from: data)
    }

    static func fetch(callSid: String) async throws -> AfterCallSummary {
        guard let path = path(callSid: callSid) else { throw URLError(.badURL) }
        let request = try APIClient.shared.makeRequest(path: path, method: "GET")
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try decode(data)
    }
}

/// BOREAL_DIALER_v821 - the last call that ended on this iPhone, so Calls > Recents can offer its summary after the
/// outcome sheet is closed. Kept for 30 minutes.
@MainActor
final class AfterCallSummaryStore: ObservableObject {
    static let shared = AfterCallSummaryStore()
    static let bannerLifetime: TimeInterval = 30 * 60

    @Published private(set) var latest: FinishedCall?
    @Published var dismissedCallSid: String?

    private init() {}

    func record(_ call: FinishedCall?) {
        guard let call, AfterCallSummaryService.pathSegment(call.callSid) != nil else { return }
        latest = call
    }

    /// The call the Recents banner offers, if it is recent and not dismissed.
    func bannerCall(now: Date = Date()) -> FinishedCall? {
        Self.bannerCall(latest: latest, dismissed: dismissedCallSid, now: now)
    }

    nonisolated static func bannerCall(latest: FinishedCall?, dismissed: String?, now: Date) -> FinishedCall? {
        guard let latest, latest.callSid != dismissed,
              now.timeIntervalSince(latest.endedAt) < bannerLifetime else { return nil }
        return latest
    }

    func clear() {
        latest = nil
        dismissedCallSid = nil
    }
}
