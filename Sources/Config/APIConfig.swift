import Foundation

struct APIConfig {
    static let BF_BASE_URL  = "https://server.boreal.financial/api"
    static let BI_BASE_URL  = "https://bi-server.boreal.financial/api"
    static let SLF_BASE_URL = "https://slf-server.boreal.financial/api"

    static var activeBaseURL: String = BF_BASE_URL

    static var baseURL: String { activeBaseURL }

    static func url(for silo: Silo) -> String {
        switch silo {
        case .bf:  return BF_BASE_URL
        case .bi:  return BI_BASE_URL
        case .slf: return SLF_BASE_URL
        }
    }
}
