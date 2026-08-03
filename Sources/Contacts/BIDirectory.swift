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
}
