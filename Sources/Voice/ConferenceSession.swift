// BOREAL_DIALER_CONFERENCE_CONTROLS_v14
import Foundation

/// Server-backed state for calls that were placed as controllable conferences.
@MainActor
final class ConferenceSession: ObservableObject {
    static let shared = ConferenceSession()

    @Published private(set) var conferenceId: String?
    @Published private(set) var selfParticipantId: String?
    @Published private(set) var remoteParticipantId: String?
    @Published private(set) var participants: [ConferenceParticipant] = []
    @Published private(set) var remoteOnHold = false
    @Published var lastError: String?

    var isActive: Bool { conferenceId != nil }

    private init() {}

    struct ConferenceParticipant: Identifiable, Decodable, Hashable {
        let id: String
        let displayName: String?
        let phoneNumber: String?
        let muted: Bool?
        let onHold: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case phoneNumber = "phone_number"
            case muted
            case onHold = "on_hold"
        }

        var label: String { displayName ?? phoneNumber ?? "Participant" }
    }

    private struct StartResponse: Decodable {
        let ok: Bool
        let conferenceId: String
        let callerParticipantId: String?
        let calleeParticipantId: String?
    }

    private struct DetailResponse: Decodable {
        let participants: [ConferenceParticipant]
    }

    @discardableResult
    func start(to number: String, contactId: String? = nil) async -> Bool {
        clear()
        var payload: [String: Any] = ["to": number]
        if let contactId { payload["contactId"] = contactId }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let request = try APIClient.shared.makeRequest(path: "/voice/calls", method: "POST", body: body)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let decoded = try JSONDecoder().decode(StartResponse.self, from: data)
            conferenceId = decoded.conferenceId
            selfParticipantId = decoded.callerParticipantId
            remoteParticipantId = decoded.calleeParticipantId
            await refresh()
            return true
        } catch {
            lastError = "Couldn't set up call controls for this call."
            return false
        }
    }

    // BOREAL_DIALER_QUICK_CALL_v16 - mode B of POST /voice/calls: ring another
    // staff member's client instead of a PSTN number.
    @discardableResult
    func startInternal(staffIdentity: String) async -> Bool {
        clear()
        do {
            let body = try JSONSerialization.data(withJSONObject: ["staffIdentity": staffIdentity])
            let request = try APIClient.shared.makeRequest(
                path: "/voice/calls", method: "POST", body: body
            )
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let decoded = try JSONDecoder().decode(StartResponse.self, from: data)
            conferenceId = decoded.conferenceId
            selfParticipantId = decoded.callerParticipantId
            remoteParticipantId = decoded.calleeParticipantId
            await refresh()
            return true
        } catch {
            lastError = "Couldn't reach that teammate."
            return false
        }
    }

    func clear() {
        conferenceId = nil
        selfParticipantId = nil
        remoteParticipantId = nil
        participants = []
        remoteOnHold = false
        lastError = nil
    }

    func refresh() async {
        guard let conferenceId else { return }
        do {
            let request = try APIClient.shared.makeRequest(path: "/voice/conferences/\(conferenceId)")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            participants = try JSONDecoder().decode(DetailResponse.self, from: data).participants
        } catch {
            // Refresh is cosmetic; controls can still operate with the known IDs.
        }
    }

    func setRemoteHold(_ hold: Bool) async {
        guard let conferenceId, let pid = remoteParticipantId else { return }
        let ok = await post("/voice/conferences/\(conferenceId)/participants/\(pid)/hold", ["hold": hold], failure: "Couldn't change hold.")
        if ok { remoteOnHold = hold }
    }

    func setMuted(_ muted: Bool, participantId: String) async {
        guard let conferenceId else { return }
        _ = await post("/voice/conferences/\(conferenceId)/participants/\(participantId)/mute", ["muted": muted], failure: "Couldn't change mute.")
        await refresh()
    }

    func addParticipant(phone: String) async {
        guard let conferenceId else { return }
        let ok = await post("/voice/conferences/\(conferenceId)/participants", ["phone": phone], failure: "Couldn't add that number to the call.")
        if ok { await refresh() }
    }

    func kick(participantId: String) async {
        guard let conferenceId else { return }
        _ = await send("/voice/conferences/\(conferenceId)/participants/\(participantId)", method: "DELETE", payload: nil, failure: "Couldn't remove that participant.")
        await refresh()
    }

    func transfer(toPhone phone: String, mode: String) async {
        guard let conferenceId else { return }
        var payload: [String: Any] = ["mode": mode, "target": ["phone": phone]]
        if let selfParticipantId { payload["initiatorParticipantId"] = selfParticipantId }
        _ = await post("/voice/conferences/\(conferenceId)/transfer", payload, failure: "Couldn't transfer the call.")
        await refresh()
    }

    func recording(op: String) async {
        guard let conferenceId else { return }
        _ = await post("/voice/conferences/\(conferenceId)/recording", ["op": op], failure: "Couldn't change recording.")
    }

    @discardableResult
    private func post(_ path: String, _ payload: [String: Any], failure: String) async -> Bool {
        await send(path, method: "POST", payload: payload, failure: failure)
    }

    @discardableResult
    private func send(_ path: String, method: String, payload: [String: Any]?, failure: String) async -> Bool {
        do {
            let body = payload.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            let request = try APIClient.shared.makeRequest(path: path, method: method, body: body)
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
            lastError = nil
            return true
        } catch {
            lastError = failure
            return false
        }
    }
}
