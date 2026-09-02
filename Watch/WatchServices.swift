import Foundation
import Network
import Security
import SwiftUI

enum WatchServiceError: Error, Equatable {
    case offline, notAuthenticated, invalidLogin, invalidResponse
    case serverCapabilityUnavailable, duplicateRequest, invalidDestination, cancelled
}

protocol WatchCredentialStore {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

final class WatchKeychainCredentialStore: WatchCredentialStore {
    private let service = "financial.boreal.dialer.watch.auth"
    private let account = "staff-access-token"
    func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func write(_ token: String) {
        clear()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)]
        SecItemAdd(query as CFDictionary, nil)
    }
    func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

actor WatchAuthService {
    static let shared = WatchAuthService()
    private let store: WatchCredentialStore
    private(set) var token: String?
    init(store: WatchCredentialStore = WatchKeychainCredentialStore()) {
        self.store = store
        token = store.read()
    }
    func restore() -> Bool { token != nil }
    /// Accepts only a credential returned by a verified Boreal OTP/device-link flow.
    func establishSession(verifiedToken: String) throws {
        guard !verifiedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WatchServiceError.invalidLogin
        }
        store.write(verifiedToken); token = verifiedToken
    }
    func startOTP(phone: String, session: URLSession = .shared) async throws {
        _ = try await otpRequest(path: "auth/otp/start", payload: ["phone": phone], session: session)
    }
    func verifyOTP(phone: String, code: String, session: URLSession = .shared) async throws {
        let data = try await otpRequest(path: "auth/otp/verify", payload: ["phone": phone, "code": code], session: session)
        struct Response: Decodable { struct Body: Decodable { let token: String }; let data: Body }
        do { try establishSession(verifiedToken: JSONDecoder().decode(Response.self, from: data).data.token) }
        catch let error as WatchServiceError { throw error }
        catch { throw WatchServiceError.invalidResponse }
    }
    /// Existing Boreal OTP is the standalone re-authentication path when an
    /// expired credential cannot be refreshed by a confirmed refresh contract.
    func recoverFromExpiration() { invalidateExpiredSession() }
    func invalidateExpiredSession() { store.clear(); token = nil }
    func logout() { store.clear(); token = nil }

    private func otpRequest(path: String, payload: [String: String], session: URLSession) async throws -> Data {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BorealAPIBaseURL") as? String,
              let base = URL(string: value), base.scheme == "https" else { throw WatchServiceError.invalidResponse }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WatchServiceError.invalidResponse }
            if http.statusCode == 401 || http.statusCode == 403 { throw WatchServiceError.invalidLogin }
            guard (200..<300).contains(http.statusCode) else { throw WatchServiceError.invalidResponse }
            return data
        } catch let error as WatchServiceError { throw error }
        catch { throw WatchServiceError.offline }
    }
}

struct WatchAPIClient {
    let baseURL: URL
    let session: URLSession
    let auth: WatchAuthService
    init?(session: URLSession = .shared, auth: WatchAuthService = .shared) {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BorealAPIBaseURL") as? String,
              let url = URL(string: value), url.scheme == "https" else { return nil }
        baseURL = url; self.session = session; self.auth = auth
    }
    func request(path: String, method: String = "GET", body: Data? = nil,
                 line: BorealLine? = nil) async throws -> Data {
        guard let token = await auth.token else { throw WatchServiceError.notAuthenticated }
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let line { request.setValue(line.rawValue, forHTTPHeaderField: "X-Silo") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WatchServiceError.invalidResponse }
            if http.statusCode == 401 { await auth.invalidateExpiredSession(); throw WatchServiceError.invalidLogin }
            guard (200..<300).contains(http.statusCode) else { throw WatchServiceError.invalidResponse }
            return data
        } catch let error as WatchServiceError { throw error }
        catch { throw WatchServiceError.offline }
    }
}

protocol WatchDirectoryService {
    func search(_ query: String, limit: Int) async throws -> [ContactSummary]
}

/// Boundary for a direct, authenticated, bounded server search. It is disabled
/// until a response contract shared by all Boreal silos is confirmed.
struct DirectWatchDirectoryService: WatchDirectoryService {
    func search(_ query: String, limit: Int = 10) async throws -> [ContactSummary] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        throw WatchServiceError.serverCapabilityUnavailable
    }
}

protocol WatchRecentsService { func fetch(limit: Int) async throws -> [RecentCall] }
struct DirectWatchRecentsService: WatchRecentsService {
    func fetch(limit: Int = 25) async throws -> [RecentCall] {
        throw WatchServiceError.serverCapabilityUnavailable
    }
}

enum WatchNetworkState { case online, offline, transitioning }
final class WatchNetworkMonitor: ObservableObject {
    @Published private(set) var state: WatchNetworkState = .transitioning
    private let monitor = NWPathMonitor(); private let queue = DispatchQueue(label: "watch.network")
    func start() { monitor.pathUpdateHandler = { [weak self] path in
        DispatchQueue.main.async { self?.state = path.status == .satisfied ? .online : .offline }
    }; monitor.start(queue: queue) }
    deinit { monitor.cancel() }
}

enum WatchOperatingMode { case companion, standalone }
enum WatchPresence { case available, offline, standaloneCellular, companionAvailable, busy }
