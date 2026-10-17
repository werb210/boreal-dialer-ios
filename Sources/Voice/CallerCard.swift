// BOREAL_DIALER_v821 - the caller card: who is calling, their company and pipeline stage, and the last note, shown on
// the CallKit ringing screen (name), the in-call screen (full card) and the Watch (name + stage).
//
// Sources, in order:
//   1. the Twilio invite's customParameters "callerName", "callerCompany", "callerStage", "contactId" (incoming calls;
//      available synchronously, so the very first CallKit report already carries the name);
//   2. GET /voice/caller-card?phone=<E.164> -> {found, contactId?, name?, company?, stage?, applicationId?, lastNote?,
//      lastContactAt?, tags?} (outgoing calls, and incoming calls whose invite has no parameters);
//   3. the existing POST /voice/resolve-caller lookup, if the caller card cannot be fetched.
import Foundation

struct CallerCard: Decodable, Equatable, Sendable {
    let found: Bool
    let contactId: String?
    let name: String?
    let company: String?
    let stage: String?
    let applicationId: String?
    let lastNote: String?
    let lastContactAt: String?
    let tags: [String]

    init(found: Bool, contactId: String? = nil, name: String? = nil, company: String? = nil, stage: String? = nil,
         applicationId: String? = nil, lastNote: String? = nil, lastContactAt: String? = nil, tags: [String] = []) {
        self.found = found
        self.contactId = Self.identifier(contactId)
        self.name = Self.clean(name)
        self.company = Self.clean(company)
        self.stage = Self.clean(stage)
        self.applicationId = Self.identifier(applicationId)
        self.lastNote = Self.clean(lastNote, limit: 500)
        self.lastContactAt = Self.clean(lastContactAt)
        self.tags = tags.compactMap { Self.clean($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case found, contactId, name, company, stage, applicationId, lastNote, lastContactAt, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            found: (try? c.decodeIfPresent(Bool.self, forKey: .found)) ?? false,
            contactId: try? c.decodeIfPresent(String.self, forKey: .contactId),
            name: try? c.decodeIfPresent(String.self, forKey: .name),
            company: try? c.decodeIfPresent(String.self, forKey: .company),
            stage: try? c.decodeIfPresent(String.self, forKey: .stage),
            applicationId: try? c.decodeIfPresent(String.self, forKey: .applicationId),
            lastNote: try? c.decodeIfPresent(String.self, forKey: .lastNote),
            lastContactAt: try? c.decodeIfPresent(String.self, forKey: .lastContactAt),
            tags: (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        )
    }

    /// Builds a card from a Twilio invite's customParameters. Nil when no caller name was sent.
    static func fromInviteParameters(_ parameters: [String: String]?) -> CallerCard? {
        guard let parameters else { return nil }
        func value(_ key: String) -> String? { parameters[key].map(decodedParameter) }
        guard let name = clean(value("callerName")) else { return nil }
        return CallerCard(found: true,
                          contactId: value("contactId"),
                          name: name,
                          company: value("callerCompany"),
                          stage: value("callerStage"))
    }

    /// Twilio carries custom parameters through SIP headers; depending on the path they can arrive form-encoded
    /// ("Tanya%20Voss" or "Tanya+Voss"). Only a value that actually contains a percent escape is decoded, so a company
    /// called "A+ Lending" with no escapes is left alone.
    static func decodedParameter(_ raw: String) -> String {
        guard raw.range(of: #"%[0-9A-Fa-f]{2}"#, options: .regularExpression) != nil else { return raw }
        let spaced = raw.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? raw
    }

    /// What the CallKit ringing screen shows: "Name · Company", or just the name.
    var callKitName: String? {
        guard found, let name else { return nil }
        guard let company else { return name }
        return "\(name) · \(company)"
    }

    /// Something worth drawing as a card (a name at least).
    var isDisplayable: Bool { found && name != nil }

    private static func clean(_ value: String?, limit: Int = 120) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    /// Ids end up in navigation and request paths: only plain identifiers survive.
    private static func identifier(_ value: String?) -> String? {
        guard let value = clean(value), value.count <= 128,
              value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return value
    }
}

/// BOREAL_DIALER_v821 - GET /voice/caller-card?phone=<E.164>.
enum CallerCardService {
    static func path(phone: String) -> String? {
        let e164 = PhoneFormat.e164(phone)
        guard e164.hasPrefix("+"), e164.dropFirst().allSatisfy(\.isNumber), e164.count >= 8,
              // "+" must travel as %2B or the server reads a space.
              let encoded = e164.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return "/voice/caller-card?phone=\(encoded)"
    }

    static func decode(_ data: Data) throws -> CallerCard {
        try JSONDecoder().decode(CallerCard.self, from: data)
    }

    static func fetch(phone: String) async throws -> CallerCard {
        guard let path = path(phone: phone) else { throw URLError(.badURL) }
        let request = try APIClient.shared.makeRequest(path: path, method: "GET")
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try decode(data)
    }
}

/// BOREAL_DIALER_v821 - the card for the call in progress, so the in-call screen does not fetch what the invite or the
/// ringing lookup already provided. Cleared when the call ends.
@MainActor
final class CallerCardStore: ObservableObject {
    static let shared = CallerCardStore()
    @Published private(set) var card: CallerCard?
    private var handleDigits: String?

    private init() {}

    func set(_ card: CallerCard, handle: String) {
        self.card = card
        handleDigits = Self.digits(handle)
    }

    /// The stored card when it belongs to `handle`.
    func card(for handle: String?) -> CallerCard? {
        guard let handle, let handleDigits, Self.digits(handle) == handleDigits else { return nil }
        return card
    }

    func clear() {
        card = nil
        handleDigits = nil
    }

    /// Last 10 digits, so "+14035550100" and "4035550100" match.
    nonisolated static func digits(_ handle: String) -> String {
        String(handle.filter(\.isNumber).suffix(10))
    }
}
