import Foundation

struct APIConfig {
    static let BASE_URL = "https://server.boreal.financial/api"

    // BOREAL_DIALER_BI_CONTACTS_v51
    // BI is NOT a silo of BF-Server's data - it is a separate deployment with
    // its own database. Only the BI CRM read paths use this; calling, SMS,
    // messages, team and calendar all stay on BASE_URL for every silo. This is
    // the same host the staff portal falls back to in src/config/api.ts.
    static let BI_BASE_URL = "https://bi-server-cse0apamgkheb9d5.canadacentral-01.azurewebsites.net/api"

    // All silos use the same server — silo is sent as X-Silo header
    static var activeBaseURL: String = BASE_URL
    static var activeSilo: Silo = .bf

    static var baseURL: String { BASE_URL }

    static func url(for silo: Silo) -> String { BASE_URL }

    static func siloHeader(for silo: Silo) -> String {
        switch silo {
        case .bf:  return "BF"
        case .bi:  return "BI"
        case .slf: return "SLF"
        }
    }
}
