import Foundation

struct APIConfig {
    static let BASE_URL = "https://server.boreal.financial/api"

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
