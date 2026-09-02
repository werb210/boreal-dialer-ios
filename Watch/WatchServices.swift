import Foundation
import Network
import Security
import SwiftUI
import WatchKit

enum WatchServiceError: Error, Equatable {
    case offline, notAuthenticated, invalidLogin, invalidResponse
    case serverCapabilityUnavailable, duplicateRequest, invalidDestination, cancelled
    case server(code: String, message: String)

    var safeMessage: String {
        switch self {
        case .server(let code, let message):
            return code == "callback_not_verified"
                ? "A verified cellular callback number is required for standalone Watch calling."
                : (message.isEmpty ? "The server could not complete the request." : message)
        case .offline: return "Network unavailable"
        case .notAuthenticated, .invalidLogin: return "Link this Apple Watch to continue"
        case .invalidDestination: return "Enter a valid phone number"
        default: return "Request unavailable"
        }
    }
}

struct WatchSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let deviceId: String
}

protocol WatchCredentialStore {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

final class WatchKeychainCredentialStore: WatchCredentialStore {
    private let service = "financial.boreal.dialer.watch.auth"
    private let account = "watch-session"
    func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return data.base64EncodedString()
    }
    func write(_ value: String) {
        clear()
        guard let data = Data(base64Encoded: value) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data]
        SecItemAdd(query as CFDictionary, nil)
    }
    func clear() { SecItemDelete([kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary) }
}

actor WatchAuthService {
    static let shared = WatchAuthService()
    private let store: WatchCredentialStore
    private(set) var session: WatchSession?
    var token: String? { session?.accessToken }

    init(store: WatchCredentialStore = WatchKeychainCredentialStore()) {
        self.store = store
        if let raw = store.read(), let data = Data(base64Encoded: raw) {
            session = try? Self.decoder.decode(WatchSession.self, from: data)
        }
    }
    func restore() -> Bool { session != nil }
    func save(_ value: WatchSession) throws {
        let data = try JSONEncoder().encode(value)
        store.write(data.base64EncodedString()); session = value
    }
    // Retained for source compatibility with older tests; production linking uses link(oneTimeCode:).
    func establishSession(verifiedToken: String) throws {
        guard !verifiedToken.isEmpty else { throw WatchServiceError.invalidLogin }
        try save(WatchSession(accessToken: verifiedToken, refreshToken: "legacy", expiresAt: .distantFuture, deviceId: "legacy"))
    }
    func link(oneTimeCode: String, client: WatchAPIClient? = nil) async throws {
        guard oneTimeCode.count == 8, oneTimeCode.allSatisfy(\.isNumber) else { throw WatchServiceError.invalidLogin }
        let api = try client ?? WatchAPIClient(auth: self)
        struct Device: Encodable { let platform = "watchos"; let name: String }
        struct Body: Encodable { let oneTimeCode: String; let device: Device }
        let body = try JSONEncoder().encode(Body(oneTimeCode: oneTimeCode,
            device: Device(name: WKInterfaceDevice.current().name)))
        let data = try await api.unauthenticated(path: "/watch/auth/link", method: "POST", body: body)
        let linked = try Self.decoder.decode(WatchSession.self, from: data)
        try save(linked)
        try await api.registerDevice()
        try await WatchPushTokenStore.shared.uploadIfPossible(client: api)
    }
    func refresh(using client: WatchAPIClient) async throws {
        guard let current = session else { throw WatchServiceError.notAuthenticated }
        struct Body: Encodable { let refreshToken, deviceId: String }
        do {
            let data = try await client.unauthenticated(path: "/watch/auth/refresh", method: "POST",
                body: JSONEncoder().encode(Body(refreshToken: current.refreshToken, deviceId: current.deviceId)))
            let rotated = try Self.decoder.decode(WatchSession.self, from: data)
            try save(rotated)
        } catch { clear(); throw error }
    }
    func clear() { store.clear(); session = nil }
    func logout(client: WatchAPIClient) async throws {
        guard let current = session else { clear(); return }
        _ = try await client.request(path: "/watch/devices/\(current.deviceId)/session", method: "DELETE")
        clear(); WatchPushTokenStore.shared.clear()
    }
    /// Local-only compatibility helper. User-facing sign out uses the revoking overload.
    func logout() { clear() }
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

struct WatchAPIClient: @unchecked Sendable {
    let baseURL: URL; let session: URLSession; let auth: WatchAuthService
    init(baseURL: URL, session: URLSession = .shared, auth: WatchAuthService = .shared) throws {
        guard baseURL.scheme == "https" else { throw WatchServiceError.invalidResponse }
        self.baseURL = baseURL; self.session = session; self.auth = auth
    }
    init(session: URLSession = .shared, auth: WatchAuthService = .shared) throws {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BorealAPIBaseURL") as? String,
              let url = URL(string: value) else { throw WatchServiceError.invalidResponse }
        try self.init(baseURL: url, session: session, auth: auth)
    }
    func unauthenticated(path: String, method: String = "GET", body: Data? = nil,
                         query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> Data {
        try await execute(path: path, method: method, body: body, query: query, headers: headers, token: nil)
    }
    func request(path: String, method: String = "GET", body: Data? = nil, line: BorealLine? = nil,
                 query: [URLQueryItem] = [], headers: [String: String] = [:], retry401: Bool = true) async throws -> Data {
        guard var current = await auth.session else { throw WatchServiceError.notAuthenticated }
        if current.expiresAt.timeIntervalSinceNow < 60 { try await auth.refresh(using: self); current = await auth.session! }
        let effectiveHeaders = headers.merging(line.map { ["X-Silo": $0.rawValue] } ?? [:]) { a, _ in a }
        do { return try await execute(path: path, method: method, body: body, query: query,
            headers: effectiveHeaders, token: current.accessToken) }
        catch WatchServiceError.invalidLogin where retry401 {
            try await auth.refresh(using: self)
            guard let fresh = await auth.session else { throw WatchServiceError.notAuthenticated }
            return try await execute(path: path, method: method, body: body, query: query, headers: effectiveHeaders, token: fresh.accessToken)
        }
    }
    private func execute(path: String, method: String, body: Data?, query: [URLQueryItem], headers: [String:String], token: String?) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url, url.scheme == "https" else { throw WatchServiceError.invalidResponse }
        var req = URLRequest(url: url); req.httpMethod = method; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw WatchServiceError.invalidResponse }
            if http.statusCode == 401 { throw WatchServiceError.invalidLogin }
            guard (200..<300).contains(http.statusCode) else {
                struct Envelope: Decodable { struct Detail: Decodable { let code, message: String }; let error: Detail }
                if let value = try? JSONDecoder().decode(Envelope.self, from: data) { throw WatchServiceError.server(code: value.error.code, message: value.error.message) }
                throw WatchServiceError.invalidResponse
            }
            return data
        } catch let error as WatchServiceError { throw error }
        catch { throw WatchServiceError.offline }
    }
    func registerDevice() async throws {
        guard let value = await auth.session else { throw WatchServiceError.notAuthenticated }
        struct Body: Encodable { let platform, appVersion, name: String }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        _ = try await request(path: "/watch/devices/\(value.deviceId)", method: "PUT", body: JSONEncoder().encode(Body(platform: "watchos", appVersion: version, name: WKInterfaceDevice.current().name)))
    }
}

protocol WatchDirectoryService { func search(_ query: String, line: BorealLine, limit: Int) async throws -> [ContactSummary] }
extension WatchDirectoryService { func search(_ query: String, limit: Int) async throws -> [ContactSummary] { try await search(query, line: .BF, limit: limit) } }
struct DirectWatchDirectoryService: WatchDirectoryService {
    let client: WatchAPIClient
    init(client: WatchAPIClient? = nil) { self.client = client ?? (try! WatchAPIClient()) }
    func search(_ query: String, line: BorealLine, limit: Int = 10) async throws -> [ContactSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines); guard q.count >= 2 else { return [] }
        let data = try await client.request(path: "/watch/contacts", line: line, query: [.init(name:"q", value:q), .init(name:"line", value:line.rawValue), .init(name:"limit", value:String(min(10,max(1,limit))))])
        struct Response: Decodable { let items: [ContactSummary] }
        return try WatchAuthService.decoder.decode(Response.self, from: data).items
    }
}
protocol WatchRecentsService { func fetch(line: BorealLine, limit: Int) async throws -> [WatchRecentCall] }
extension WatchRecentsService { func fetch(limit: Int) async throws -> [WatchRecentCall] { try await fetch(line: .BF, limit: limit) } }
struct DirectWatchRecentsService: WatchRecentsService {
    let client: WatchAPIClient
    init(client: WatchAPIClient? = nil) { self.client = client ?? (try! WatchAPIClient()) }
    func fetch(line: BorealLine, limit: Int = 25) async throws -> [WatchRecentCall] {
        struct DTO: Decodable { let id, number: String; let contactName: String?; let direction: WatchCallDirection; let occurredAt: Date; let line: BorealLine; let status: String? }
        struct Response: Decodable { let items: [DTO] }
        let data = try await client.request(path: "/watch/calls/recent", line: line, query: [.init(name:"line",value:line.rawValue),.init(name:"limit",value:String(min(25,max(1,limit))))])
        return try WatchAuthService.decoder.decode(Response.self, from:data).items.map { WatchRecentCall(id:$0.id,name:$0.contactName,number:$0.number,direction:$0.direction,occurredAt:$0.occurredAt,line:$0.line,status:$0.status) }
    }
}

enum WatchNetworkState { case online, offline, transitioning }
final class WatchNetworkMonitor: ObservableObject { @Published private(set) var state: WatchNetworkState = .transitioning; private let monitor=NWPathMonitor(); private let queue=DispatchQueue(label:"watch.network"); func start(){ monitor.pathUpdateHandler={ [weak self] p in DispatchQueue.main.async { self?.state = p.status == .satisfied ? .online:.offline }}; monitor.start(queue:queue)}; deinit{monitor.cancel()} }
enum WatchOperatingMode: Equatable { case companion, standalone }
enum WatchPresence { case available, offline, standaloneCellular, companionAvailable, busy }
