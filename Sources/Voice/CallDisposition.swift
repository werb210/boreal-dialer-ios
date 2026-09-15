// BOREAL_DIALER_POST_CALL_DISPOSITION_v201
// The post-call workflow. Everything it triggers - setting the disposition,
// creating the follow-up task, writing the CRM timeline note - already happens
// server side in one call (BF_SERVER_CALL_DISPOSITION_v145). The dialer's job is
// only to ask the question and POST the answer, so the rules stay in one place
// and the Watch, portal and phone cannot drift apart on them.
import Foundation

/// Mirrors CALL_DISPOSITIONS in src/modules/calls/callDisposition.ts.
/// The raw values must match exactly - the server rejects anything else with
/// unknown_disposition rather than guessing.
enum CallDisposition: String, CaseIterable, Identifiable, Sendable {
    case connected
    case leftVoicemail = "left_voicemail"
    case noAnswer = "no_answer"
    case followUp = "follow_up"
    case notInterested = "not_interested"
    case doNotContact = "do_not_contact"
    case demoBooked = "demo_booked"
    case documentsPromised = "documents_promised"
    case needsLenderReview = "needs_lender_review"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .leftVoicemail: return "Left voicemail"
        case .noAnswer: return "No answer"
        case .followUp: return "Follow-up required"
        case .notInterested: return "Not interested"
        case .doNotContact: return "Do not contact"
        case .demoBooked: return "Demo booked"
        case .documentsPromised: return "Documents promised"
        case .needsLenderReview: return "Needs lender review"
        }
    }

    /// What the server will do besides recording the outcome. Shown to staff so
    /// the automatic task is never a surprise. Mirrors DISPOSITION_FOLLOWUP.
    var followUpNote: String? {
        switch self {
        case .followUp: return "Creates a follow-up task in 2 days"
        case .documentsPromised: return "Creates a task to collect documents in 3 days"
        case .needsLenderReview: return "Creates a lender review task tomorrow"
        case .demoBooked: return "Creates a demo prep task tomorrow"
        default: return nil
        }
    }

    /// Ordering for the sheet: the outcomes staff pick most often first.
    static var ordered: [CallDisposition] {
        [.connected, .leftVoicemail, .noAnswer, .followUp, .documentsPromised,
         .demoBooked, .needsLenderReview, .notInterested, .doNotContact]
    }
}

struct DispositionResult: Decodable, Sendable {
    let callId: String?
    let disposition: String?
    let followUpCreated: Bool?
}

private struct DispositionEnvelope: Decodable {
    let success: Bool?
    let data: DispositionResult?
    let error: String?
}

enum CallDispositionService {
    /// POST /api/telephony/calls/{id}/disposition
    /// `id` may be our call id or the Twilio CallSid - the server accepts either
    /// (BF_SERVER_CALL_REF_v161), which matters because the dialer usually only
    /// has the CallSid.
    static func record(callRef: String, disposition: CallDisposition) async throws -> DispositionResult {
        let trimmed = callRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DispositionError.missingCallReference }

        let payload = ["disposition": disposition.rawValue]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try APIClient.shared.makeRequest(
            path: "/telephony/calls/\(trimmed)/disposition",
            method: "POST",
            body: body
        )
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        let envelope = try JSONDecoder().decode(DispositionEnvelope.self, from: data)
        guard envelope.success == true, let result = envelope.data else {
            throw DispositionError.rejected(envelope.error ?? "unknown")
        }
        return result
    }
}

enum DispositionError: LocalizedError {
    case missingCallReference
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .missingCallReference:
            return "That call has no reference to record against."
        case .rejected(let reason):
            // Surface the server's own reason. call_not_found in particular means
            // the call was logged against a different staff user, which is a real
            // condition staff need to see rather than a generic failure.
            return "Could not save the outcome (\(reason))."
        }
    }
}

// BOREAL_DIALER_CALL_SUMMARY_v246
// BF-Server v245 writes an AI summary once Twilio finishes the transcript,
// usually a few minutes after hang-up. The sheet polls while it is open; the
// summary also lands on the contact timeline, so closing the sheet loses nothing.
struct CallSummaryResult: Decodable, Sendable, Equatable {
    let status: String
    let summary: String?
}

private struct CallSummaryEnvelope: Decodable {
    let status: String?
    let data: CallSummaryResult?
}

enum CallSummaryService {
    static let pollIntervalNanoseconds: UInt64 = 20_000_000_000
    static let maxAttempts = 15

    static func decode(_ data: Data) throws -> CallSummaryResult {
        let envelope = try JSONDecoder().decode(CallSummaryEnvelope.self, from: data)
        guard let result = envelope.data else { throw URLError(.cannotParseResponse) }
        return result
    }

    static func shouldKeepPolling(_ result: CallSummaryResult?, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        guard let result else { return true }
        return result.status == "pending"
    }

    static func fetch(callSid: String) async throws -> CallSummaryResult {
        let trimmed = callSid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw URLError(.badURL)
        }
        let request = try APIClient.shared.makeRequest(path: "/calls/summary?callSid=\(encoded)", method: "GET")
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try decode(data)
    }
}
