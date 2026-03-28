import Foundation

final class TelephonyService {

    static let shared = TelephonyService()

    private init() {}

    @discardableResult
    func endCall(uuid: String) async throws -> Bool {
        let (_, response) = try await APIClient.shared.perform(
            path: "/api/calls/\(uuid)/end",
            method: "POST"
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200...299).contains(httpResponse.statusCode)
    }
}
