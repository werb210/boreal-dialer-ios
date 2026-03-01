import Foundation
import TwilioVoice

@MainActor
final class VoiceManager: NSObject, ObservableObject {

    static let shared = VoiceManager()

    @Published private(set) var activeCall: Call?

    private var accessToken: String?
    private var pendingInvite: CallInvite?

    private override init() {
        super.init()
    }

    func initialize() async {
        guard let token = await fetchToken() else { return }

        accessToken = token
        TwilioVoiceSDK.audioDevice = DefaultAudioDevice()
        sendPresence(status: "online")
    }

    private func fetchToken() async -> String? {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/voice/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let data = try await AuthService.shared.performAuthorizedRequest(request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            return response.token
        } catch {
            print("Token fetch failed:", error)
            return nil
        }
    }

    func startCall(clientId: String) async {
        guard let token = accessToken else { return }

        let options = ConnectOptions(accessToken: token) { builder in
            builder.params = ["clientId": clientId]
        }

        activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
        sendPresence(status: "busy")
    }

    func acceptCall(invite: CallInvite) {
        activeCall = invite.accept(with: self)
        pendingInvite = nil
        sendPresence(status: "busy")
    }

    func rejectCall(invite: CallInvite) {
        invite.reject()
        if pendingInvite?.uuid == invite.uuid {
            pendingInvite = nil
        }
    }

    func sendPresence(status: String) {
        Task {
            let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
            let url = baseURL.appendingPathComponent("api/voice/presence")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = true
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: String] = [
                "status": status,
                "source": "dialer"
            ]

            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await AuthService.shared.performAuthorizedRequest(request)
        }
    }
}

extension VoiceManager: CallDelegate {

    func callDidStartRinging(_ call: Call) {
        print("Ringing")
    }

    func callDidConnect(_ call: Call) {
        print("Connected")
        sendPresence(status: "busy")
        notifyServerStatus(status: "connected")
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
        print("Disconnected")
        activeCall = nil
        sendPresence(status: "online")
        notifyServerStatus(status: "completed")
    }

    private func notifyServerStatus(status: String) {
        Task {
            let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
            let url = baseURL.appendingPathComponent("api/voice/status")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = true
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = [
                "callStatus": status
            ]

            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await AuthService.shared.performAuthorizedRequest(request)
        }
    }
}

extension VoiceManager: NotificationDelegate {

    func callInviteReceived(_ callInvite: CallInvite) {
        pendingInvite = callInvite
        DispatchQueue.main.async {
            IncomingCallController.present(invite: callInvite)
        }
    }

    func cancelledCallInviteReceived(_ cancelledCallInvite: CancelledCallInvite, error: (any Error)?) {
        if pendingInvite?.callSid == cancelledCallInvite.callSid {
            pendingInvite = nil
        }
    }
}

private struct TokenResponse: Decodable {
    let token: String
}
