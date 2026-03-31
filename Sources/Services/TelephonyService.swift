import Foundation

final class TelephonyService {

    static let shared = TelephonyService()

    private init() {}

    @discardableResult
    func endCall(uuid: String) async throws -> Bool {
        let request = try APIClient.shared.makeRequest(
            path: "/calls/\(uuid)/end",
            method: "POST"
        )

        _ = try await APIClient.shared.makeAuthorizedRequest(request)
        return true
    }
}
