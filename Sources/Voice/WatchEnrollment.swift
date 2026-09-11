import Foundation

// BOREAL_DIALER_WATCH_ENROLL_v146
// Completes the Watch pairing handshake, which was built on every side except
// this one.
//
// What already existed: BF-Server issues an 8-digit code from
// POST /api/watch/auth/enrollment; WatchBridge.sendEnrollment(_:) transfers a
// code to the wrist; WatchEventStore decodes it and calls
// WatchAuthService.link(oneTimeCode:). What did not exist was anything that
// asked the server for a code and handed it to sendEnrollment — that function
// had no callers, so the Watch never received a code, never linked, and
// therefore had no token. That single gap is why the Watch could not sync,
// could not place a call, and could not receive one: all three paths go
// through an authenticated WatchAPIClient.

@MainActor
public final class WatchEnrollment {

    public static let shared = WatchEnrollment()

    private var inFlight = false
    /// Codes are valid for five minutes server-side; re-minting sooner is waste.
    private var lastMintedAt: Date?
    private let reMintAfter: TimeInterval = 240

    private init() {}

    public enum EnrollError: Error, Equatable {
        case notStaff
        case requestFailed(Int)
        case malformedResponse
    }

    struct EnrollmentResponse: Decodable {
        let oneTimeCode: String
        let expiresAt: String?
    }

    /// Parses the enrollment response. Split out so the contract is testable
    /// without a network or a paired device.
    static func parse(_ data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(EnrollmentResponse.self, from: data) else {
            throw EnrollError.malformedResponse
        }
        let code = decoded.oneTimeCode.trimmingCharacters(in: .whitespaces)
        guard code.count == 8, code.allSatisfy({ $0.isNumber }) else {
            throw EnrollError.malformedResponse
        }
        return code
    }

    /// True when enough time has passed that a fresh code is worth minting.
    func shouldMint(now: Date = Date()) -> Bool {
        guard let last = lastMintedAt else { return true }
        return now.timeIntervalSince(last) >= reMintAfter
    }

    /// Mints a code and pushes it to the wrist. Safe to call on every foreground:
    /// the Watch ignores the code once it holds a token, and re-minting is rate
    /// limited here so a user flipping in and out of the app does not hammer the
    /// endpoint.
    @discardableResult
    public func enrollWatchIfNeeded(force: Bool = false) async -> Bool {
        guard !inFlight else { return false }
        guard force || shouldMint() else { return false }
        inFlight = true
        defer { inFlight = false }

        do {
            let request = try APIClient.shared.authorizedRequest(
                APIClient.shared.makeRequest(path: "/api/watch/auth/enrollment", method: "POST")
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                if status == 403 { throw EnrollError.notStaff }
                throw EnrollError.requestFailed(status)
            }
            let code = try WatchEnrollment.parse(data)
            WatchBridge.shared.sendEnrollment(code)
            lastMintedAt = Date()
            return true
        } catch {
            // Pairing is best-effort. A failure here must never block app start;
            // the next foreground retries.
            return false
        }
    }
}
