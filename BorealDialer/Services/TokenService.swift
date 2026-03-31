import Foundation

struct TokenResponse: Decodable {
    let success: Bool
    let data: TokenData

    struct TokenData: Decodable {
        let token: String
        let identity: String
    }
}

enum TokenServiceError: LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidStatusCode(Int)
    case emptyResponse
    case invalidContract(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Token endpoint URL is invalid."
        case .requestFailed(let error):
            return "Token request failed: \(error.localizedDescription)"
        case .invalidStatusCode(let code):
            return "Token request returned unexpected status code: \(code)"
        case .emptyResponse:
            return "Token request returned empty response body."
        case .invalidContract(let message):
            return "Invalid token contract: \(message)"
        }
    }
}

final class TokenService {
    static let shared = TokenService()
    private init() {}

    func fetchToken(completion: @escaping (Result<TokenResponse.TokenData, Error>) -> Void) {
        let endpoint = AppConfig.serverBaseURL.appendingPathComponent("telephony/token")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(TokenServiceError.requestFailed(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(TokenServiceError.invalidContract("response is not HTTP")))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(TokenServiceError.invalidStatusCode(httpResponse.statusCode)))
                return
            }

            guard let data, !data.isEmpty else {
                completion(.failure(TokenServiceError.emptyResponse))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
                guard decoded.success else {
                    completion(.failure(TokenServiceError.invalidContract("success=false")))
                    return
                }

                guard !decoded.data.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    completion(.failure(TokenServiceError.invalidContract("token is empty")))
                    return
                }

                guard !decoded.data.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    completion(.failure(TokenServiceError.invalidContract("identity is empty")))
                    return
                }

                completion(.success(decoded.data))
            } catch {
                completion(.failure(TokenServiceError.invalidContract("failed to decode: \(error.localizedDescription)")))
            }
        }.resume()
    }
}
