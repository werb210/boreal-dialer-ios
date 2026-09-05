import XCTest
@testable import BorealDialerWatch

final class WatchAuthReliabilityTests: XCTestCase {
    private final class MemoryCredentialStore: WatchCredentialStore {
        var value: String?
        func read() -> String? { value }
        func write(_ token: String) { value = token }
        func clear() { value = nil }
    }

    // BOREAL_DIALER_WATCH_TRANSPORT_SEAM_v27 - a plain static handler read by the
    // client's injected transport. URLProtocol interception does not run on the
    // watchOS simulator, so the previous URLProtocol subclass never fired.
    private final class StubURLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    }

    private let baseURL = URL(string: "https://watch.test")!

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testSuccessfulRefreshRotatesAndPersistsSession() async throws {
        let (auth, store, client, original) = try await fixture()
        let rotated = session(access: "access-B", refresh: "refresh-B")
        StubURLProtocol.handler = { [self] request in
            XCTAssertEqual(request.url?.path, "/watch/auth/refresh")
            return response(for: request, status: 200, data: sessionJSON(rotated))
        }

        try await auth.refresh(using: client)

        let current = await auth.session
        XCTAssertEqual(current, rotated)
        XCTAssertNotEqual(current, original)
        XCTAssertEqual(try persistedSession(in: store), rotated)
    }

    func testUnauthorizedRefreshRevokesLocalAuthentication() async throws {
        let (auth, store, client, _) = try await fixture()
        StubURLProtocol.handler = { [self] request in response(for: request, status: 401) }

        await assertServiceError(.invalidLogin) { try await auth.refresh(using: client) }

        let current = await auth.session
        XCTAssertNil(current)
        XCTAssertNil(store.value)
    }

    func testOfflineRefreshPreservesAuthentication() async throws {
        let (auth, store, client, original) = try await fixture()
        let persisted = store.value
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await assertServiceError(.offline) { try await auth.refresh(using: client) }

        let current = await auth.session
        XCTAssertEqual(current, original)
        XCTAssertEqual(store.value, persisted)
    }

    func testServerFailurePreservesAuthentication() async throws {
        let (auth, store, client, original) = try await fixture()
        let persisted = store.value
        StubURLProtocol.handler = { [self] request in
            response(for: request, status: 500,
                     data: #"{"error":{"code":"temporarily_unavailable","message":"Try again"}}"#.data(using: .utf8)!)
        }

        await assertServiceError(.server(code: "temporarily_unavailable", message: "Try again")) {
            try await auth.refresh(using: client)
        }

        let current = await auth.session
        XCTAssertEqual(current, original)
        XCTAssertEqual(store.value, persisted)
    }

    func testMalformedRefreshResponsePreservesAuthentication() async throws {
        let (auth, store, client, original) = try await fixture()
        let persisted = store.value
        StubURLProtocol.handler = { [self] request in
            response(for: request, status: 200, data: Data("not-json".utf8))
        }

        do {
            try await auth.refresh(using: client)
            XCTFail("Malformed refresh data must throw")
        } catch {
            XCTAssertFalse(error is WatchServiceError)
        }
        let current = await auth.session
        XCTAssertEqual(current, original)
        XCTAssertEqual(store.value, persisted)
    }

    func testAuthenticatedRequestRefreshesAndRetriesExactlyOnce() async throws {
        let (auth, _, client, _) = try await fixture()
        let rotated = session(access: "access-B", refresh: "refresh-B")
        var protectedRequests = 0
        var refreshRequests = 0
        StubURLProtocol.handler = { [self] request in
            if request.url?.path == "/watch/auth/refresh" {
                refreshRequests += 1
                return response(for: request, status: 200, data: sessionJSON(rotated))
            }
            protectedRequests += 1
            if protectedRequests == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-A")
                return response(for: request, status: 401)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-B")
            return response(for: request, status: 200, data: Data("success".utf8))
        }

        let data = try await client.request(path: "/watch/protected")

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "success")
        XCTAssertEqual(refreshRequests, 1)
        XCTAssertEqual(protectedRequests, 2)
        let current = await auth.session
        XCTAssertEqual(current, rotated)
    }

    func testSecondUnauthorizedResponseDoesNotStartAnotherRefreshLoop() async throws {
        let (auth, _, client, _) = try await fixture()
        let rotated = session(access: "access-B", refresh: "refresh-B")
        var protectedRequests = 0
        var refreshRequests = 0
        StubURLProtocol.handler = { [self] request in
            if request.url?.path == "/watch/auth/refresh" {
                refreshRequests += 1
                return response(for: request, status: 200, data: sessionJSON(rotated))
            }
            protectedRequests += 1
            return response(for: request, status: 401)
        }

        await assertServiceError(.invalidLogin) { try await client.request(path: "/watch/protected") }

        XCTAssertEqual(refreshRequests, 1)
        XCTAssertEqual(protectedRequests, 2)
    }

    func testBadConfigurationThrowsInsteadOfCrashingDirectoryService() async {
        let service = DirectWatchDirectoryService(makeClient: { throw WatchServiceError.invalidResponse })
        await assertServiceError(.invalidResponse) { _ = try await service.search("Ada", line: .BF, limit: 10) }
    }

    func testBadConfigurationThrowsInsteadOfCrashingRecentsService() async {
        let service = DirectWatchRecentsService(makeClient: { throw WatchServiceError.invalidResponse })
        await assertServiceError(.invalidResponse) { _ = try await service.fetch(line: .BF, limit: 10) }
    }

    private func fixture() async throws -> (WatchAuthService, MemoryCredentialStore, WatchAPIClient, WatchSession) {
        let store = MemoryCredentialStore()
        let auth = WatchAuthService(store: store)
        let original = session(access: "access-A", refresh: "refresh-A")
        try await auth.save(original)
        let client = try WatchAPIClient(baseURL: baseURL, auth: auth, transport: { req in
            guard let handler = StubURLProtocol.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(req)
            return (data, response)
        })
        return (auth, store, client, original)
    }

    private func session(access: String, refresh: String) -> WatchSession {
        // BOREAL_DIALER_WATCH_TEST_DATE_v28 - the server JSON round-trips expiresAt
        // through ISO8601 (whole seconds) and the decoder uses .iso8601, so the
        // fixture date must be whole seconds too. Otherwise the decoded session's
        // expiresAt differs from this one by a fraction of a second and every
        // rotation assertion (current == rotated) fails.
        let expiresAt = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3_600).rounded(.down))
        return WatchSession(accessToken: access, refreshToken: refresh,
                            expiresAt: expiresAt, deviceId: "watch-1")
    }

    private func sessionJSON(_ session: WatchSession) -> Data {
        let formatter = ISO8601DateFormatter()
        return try! JSONSerialization.data(withJSONObject: [
            "accessToken": session.accessToken, "refreshToken": session.refreshToken,
            "expiresAt": formatter.string(from: session.expiresAt), "deviceId": session.deviceId
        ])
    }

    private func response(for request: URLRequest, status: Int, data: Data = Data()) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
    }

    private func persistedSession(in store: MemoryCredentialStore) throws -> WatchSession? {
        guard let raw = store.value, let data = Data(base64Encoded: raw) else { return nil }
        return try JSONDecoder().decode(WatchSession.self, from: data)
    }

    private func assertServiceError(
        _ expected: WatchServiceError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? WatchServiceError, expected, file: file, line: line)
        }
    }
}
