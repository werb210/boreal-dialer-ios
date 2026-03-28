import Foundation

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
}
