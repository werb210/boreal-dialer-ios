import Foundation

enum API {

    static func registerVoIPToken(_ token: String) async {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/voice/device-token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let accessToken = try? await AuthService.shared.getValidAccessToken() else {
            return
        }

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = [
            "deviceToken": token,
            "platform": "ios"
        ]

        request.httpBody = try? JSONEncoder().encode(body)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func answerCall(uuid: String) async {
        await updateCallState(path: "api/voice/calls/answer", id: uuid)
    }

    static func endCall(uuid: String) async {
        await updateCallState(path: "api/voice/calls/end", id: uuid)
    }

    private static func updateCallState(path: String, id: String) async {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let accessToken = try? await AuthService.shared.getValidAccessToken() else {
            return
        }

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["id": id])

        _ = try? await URLSession.shared.data(for: request)
    }
}
