import Foundation

struct AuthResponse: Decodable {
    let token: String
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case token
        case accessToken
        case refreshToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try container.decodeIfPresent(String.self, forKey: .token)
            ?? container.decodeIfPresent(String.self, forKey: .accessToken) {
            self.token = token
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.token,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing auth token")
            )
        }

        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
    }
}
