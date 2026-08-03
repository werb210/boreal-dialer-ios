// BOREAL_DIALER_BI_CONTACTS_v51
import Foundation

struct BIContactRow: Decodable {
    let id: String
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let phoneE164: String?
    let companyName: String?
    let outreachStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phoneE164 = "phone_e164"
        case companyName = "company_name"
        case outreachStatus = "outreach_status"
    }

    var asCRMContact: CRMContact {
        CRMContact(id: id, name: fullName, firstName: firstName, lastName: lastName,
                   email: email, phone: phoneE164, companyName: companyName,
                   leadStatus: outreachStatus)
    }
}

struct BICompanyRow: Decodable {
    let id: String
    let legalName: String?
    let operatingName: String?
    let contactCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case legalName = "legal_name"
        case operatingName = "operating_name"
        case contactCount = "contact_count"
    }

    var asCRMCompany: CRMCompany {
        let trimmedOperating = operatingName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = (trimmedOperating?.isEmpty == false) ? trimmedOperating : legalName
        return CRMCompany(id: id, name: preferred, contactCount: contactCount)
    }
}

struct BIListEnvelope<Row: Decodable>: Decodable {
    let data: [Row]
}

// BOREAL_DIALER_BI_ACTIVITY_v52
// Rows from GET /api/v1/bi/crm/outreach/contacts/:id/activity.
//
// NOT /crm/contacts/:id/timeline, which looks like the right endpoint and is
// not: it selects `summary, metadata` from bi_contact_activity and neither
// column exists in either of the two migrations that create that table
// (bi_marketing_foundation_v108 gives kind/payload/occurred_at,
// outreach_crm_v251 gives event_type/outcome/body/meta/created_at). That route
// 500s on every call. The outreach endpoint below is the one the staff portal's
// BI contact page uses, and it selects the v251 columns.
struct BIActivityRow: Decodable {
    let id: String
    let eventType: String?
    let outcome: String?
    let body: String?
    let actorName: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, outcome, body
        case eventType = "event_type"
        case actorName = "actor_name"
        case createdAt = "created_at"
    }

    // bi-server's event types are call / demo / sms / email / note / task /
    // meeting, which the shared TimelineEntry already knows how to draw.
    var asTimelineEntry: TimelineEntry {
        let kind = eventType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = outcome?.trimmingCharacters(in: .whitespacesAndNewlines)

        var heading: String?
        if let kind, !kind.isEmpty {
            if let result, !result.isEmpty {
                heading = "\(kind.capitalized) · \(result)"
            } else {
                heading = kind.capitalized
            }
        }

        return TimelineEntry(
            kind: kind,
            id: id,
            ts: createdAt,
            title: heading,
            body: body,
            extra: actorName
        )
    }
}

struct BIActivityEnvelope: Decodable {
    let events: [BIActivityRow]
}

enum BIDirectory {
    private static func query(_ base: String, search: String) -> String {
        guard !search.isEmpty,
              let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return base }
        return "\(base)&q=\(encoded)"
    }

    private static func fetch<Row: Decodable>(_ path: String) async throws -> [Row] {
        let request = try APIClient.shared.makeRequest(path: path, baseURL: APIConfig.BI_BASE_URL)
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try JSONDecoder().decode(BIListEnvelope<Row>.self, from: data).data
    }

    static func contacts(search: String) async throws -> [CRMContact] {
        let rows: [BIContactRow] = try await fetch(query("/v1/bi/crm/contacts?pageSize=200", search: search))
        return rows.map(\.asCRMContact)
    }

    static func companies(search: String) async throws -> [CRMCompany] {
        let rows: [BICompanyRow] = try await fetch(query("/v1/bi/crm/companies?pageSize=200", search: search))
        return rows.map(\.asCRMCompany)
    }

    // BOREAL_DIALER_BI_ACTIVITY_v52 - this envelope is { ok, events }, not the
    // { status, data } the list endpoints use, so it cannot share `fetch`.
    static func activity(contactId: String) async throws -> [TimelineEntry] {
        let request = try APIClient.shared.makeRequest(
            path: "/v1/bi/crm/outreach/contacts/\(contactId)/activity?limit=100",
            baseURL: APIConfig.BI_BASE_URL
        )
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try JSONDecoder().decode(BIActivityEnvelope.self, from: data).events.map(\.asTimelineEntry)
    }
}
