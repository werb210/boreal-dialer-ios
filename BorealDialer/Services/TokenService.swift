import Foundation

struct TokenResponse: Decodable {
    let success: Bool
    let data: TokenData?
    struct TokenData: Decodable { let token: String }
}

final class TokenService {
    static let shared = TokenService()
    private init() {}

    func fetchToken(completion: @escaping (Result<String, Error>) -> Void) {
        let url = AppConfig.serverBaseURL.appendingPathComponent("/telephony/token")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(error)); return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "token", code: -1)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
                if let token = decoded.data?.token {
                    completion(.success(token))
                } else {
                    completion(.failure(NSError(domain: "token", code: -2)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
