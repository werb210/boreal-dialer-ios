import Foundation

struct StartCallResponse: Decodable {
    struct CallPayload: Decodable {
        let id: String
    }

    let call: CallPayload
}

enum CallStatus: String {
    case initiated
    case ringing
    case inProgress = "in-progress"
    case completed
    case failed
}

final class DialerService {
    static let shared = DialerService()

    private(set) var accessToken: String?
    private(set) var identity: String?
    private var isCalling = false
    private var isFetchingToken = false
    private var tokenWaiters: [CheckedContinuation<String, Error>] = []
    private let callQueue = DispatchQueue(label: "dialer.call.lock")
    private let tokenQueue = DispatchQueue(label: "dialer.token.lock")
    private init() {}

    func ensureValidToken(authToken: String) async throws {
        if let token = currentToken(), !token.isEmpty {
            return
        }
        _ = try await fetchToken(authToken: authToken)
    }

    func fetchToken(authToken: String) async throws -> String {
        if let token = currentToken(), !token.isEmpty {
            return token
        }

        return try await withCheckedThrowingContinuation { continuation in
            var shouldStartFetch = false

            tokenQueue.sync {
                if let token = accessToken, !token.isEmpty {
                    continuation.resume(returning: token)
                    return
                }

                tokenWaiters.append(continuation)
                if !isFetchingToken {
                    isFetchingToken = true
                    shouldStartFetch = true
                }
            }

            guard shouldStartFetch else {
                return
            }

            Task {
                do {
                    let token = try await self.fetchTokenFromServer(authToken: authToken)
                    self.finishTokenFetch(result: .success(token))
                } catch {
                    self.finishTokenFetch(result: .failure(error))
                }
            }
        }
    }

    private func fetchTokenFromServer(authToken: String) async throws -> String {
        guard !authToken.isEmpty else {
            throw APIClientError.httpError(statusCode: 401, body: "Missing auth token")
        }

        let data = try await APIClient.request(
            path: "dialer/token",
            method: "GET",
            token: authToken
        )

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["token"] as? String,
            !token.isEmpty
        else {
            throw NSError(domain: "invalid_token", code: 0)
        }

        print("[DialerService] token fetched")
        accessToken = token
        identity = json["identity"] as? String
        return token
    }

    private func finishTokenFetch(result: Result<String, Error>) {
        let waiters: [CheckedContinuation<String, Error>] = tokenQueue.sync {
            isFetchingToken = false
            let pending = tokenWaiters
            tokenWaiters.removeAll()
            return pending
        }

        waiters.forEach { waiter in
            switch result {
            case .success(let token):
                waiter.resume(returning: token)
            case .failure(let error):
                waiter.resume(throwing: error)
            }
        }
    }

    private func currentToken() -> String? {
        tokenQueue.sync { accessToken }
    }

    func startCall(to: String, authToken: String) async throws -> String {
        guard !authToken.isEmpty else {
            throw APIClientError.httpError(statusCode: 401, body: "Missing auth token")
        }

        let canStartCall = callQueue.sync { () -> Bool in
            guard !isCalling else { return false }
            isCalling = true
            return true
        }

        guard canStartCall else {
            print("Call blocked: already in progress")
            throw NSError(domain: "call_in_progress", code: 0)
        }
        defer {
            callQueue.sync {
                isCalling = false
            }
        }

        try await ensureValidToken(authToken: authToken)

        let requestBody: [String: Any] = ["to": to]
        let data = try await requestWithAuthRetry(authToken: authToken) {
            try await APIClient.request(
                path: "call/start",
                method: "POST",
                body: requestBody,
                token: authToken
            )
        }
        if data.isEmpty {
            print("Warning: empty call start response")
        }

        let decoded = try JSONDecoder().decode(StartCallResponse.self, from: data)
        print("[DialerService] call started")
        return decoded.call.id
    }

    func sendCallStatus(status: String, callId: String, authToken: String) async throws {
        guard !authToken.isEmpty else {
            throw APIClientError.httpError(statusCode: 401, body: "Missing auth token")
        }

        let alignedStatus = mapStatus(status).rawValue

        do {
            _ = try await requestWithAuthRetry(authToken: authToken) {
                try await APIClient.request(
                    path: "voice/status",
                    method: "POST",
                    body: ["callId": callId, "status": alignedStatus],
                    token: authToken
                )
            }
            print("[DialerService] status sent")
        } catch {
            print("Failed to report call status:", error)
        }
    }

    private func requestWithAuthRetry(
        authToken: String,
        request: () async throws -> Data
    ) async throws -> Data {
        let maxAttempts = 4
        var attempt = 0
        var hasRefreshedAuth = false

        while attempt < maxAttempts {
            do {
                return try await request()
            } catch APIClientError.authExpired {
                guard !hasRefreshedAuth else { throw APIClientError.authExpired }
                hasRefreshedAuth = true
                tokenQueue.sync { accessToken = nil }
                _ = try await fetchToken(authToken: authToken)
            } catch APIClientError.httpError(let statusCode, _) where (500...599).contains(statusCode) {
                attempt += 1
                guard attempt < maxAttempts else {
                    throw APIClientError.httpError(statusCode: statusCode, body: "Server error after retries")
                }
                let delayNs = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: delayNs)
            } catch let urlError as URLError where urlError.code == .timedOut {
                attempt += 1
                guard attempt < maxAttempts else { throw urlError }
                let delayNs = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: delayNs)
            } catch {
                throw error
            }
        }

        throw APIClientError.invalidResponse
    }

    func debugValidateEndpoints() async {
        let testEndpoints = [
            "dialer/token",
            "call/start",
            "voice/status"
        ]

        for path in testEndpoints {
            guard let baseURL = URL(string: Environment.serverURL) else { continue }
            let url = baseURL.appendingPathComponent(path)
            print("VALIDATING:", url.absoluteString)
        }
    }



    private func retryWithBackoff<T>(
        retries: Int = 3,
        initialDelay: Double = 1.0,
        task: @escaping () async throws -> T
    ) async throws -> T {
        var delay = initialDelay

        for attempt in 0..<retries {
            do {
                return try await task()
            } catch {
                if attempt == retries - 1 {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
            }
        }

        throw APIClientError.invalidResponse
    }

    private func mapStatus(_ status: String) -> CallStatus {
        switch status.lowercased() {
        case "initiated":
            return .initiated
        case "ringing":
            return .ringing
        case "in-progress", "inprogress", "connected":
            return .inProgress
        case "completed":
            return .completed
        default:
            return .failed
        }
    }
}
