import Foundation

struct AuthResponse: Decodable {
    let status: String
    let data: AuthTokenData

    struct AuthTokenData: Decodable {
        let token: String
    }
}
