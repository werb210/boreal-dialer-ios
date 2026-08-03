// BOREAL_DIALER_RESOLVE_CALLER_CONTRACT_v45
import Foundation

struct ResolvedCaller: Decodable {
    let ok: Bool?
    let matched: Bool?
    let isStaff: Bool?
    let name: String?
    let contactId: String?
    let companyName: String?
    let applicationId: String?
    let applicationName: String?
    let userId: String?

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// The caller's name, or nil when the server did not match the number.
    var displayName: String? {
        guard matched == true else { return nil }
        return Self.trimmed(name)
    }

    var company: String? {
        Self.trimmed(companyName)
    }

    /// "Name · Company" when both are known, otherwise just the name.
    var display: String? {
        guard let displayName else { return nil }
        guard let company else { return displayName }
        return "\(displayName) · \(company)"
    }
}

enum CallerResolver {
    /// POST /api/voice/resolve-caller.
    static func resolve(phone: String, conferenceFriendly: String? = nil) async throws -> ResolvedCaller {
        var payload: [String: String] = ["phone": phone]
        if let conferenceFriendly, !conferenceFriendly.isEmpty {
            payload["conferenceFriendly"] = conferenceFriendly
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try APIClient.shared.makeRequest(
            path: "/voice/resolve-caller",
            method: "POST",
            body: body
        )
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try JSONDecoder().decode(ResolvedCaller.self, from: data)
    }
}
