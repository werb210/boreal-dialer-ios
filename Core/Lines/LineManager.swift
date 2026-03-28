import Foundation

@MainActor
final class LineManager: ObservableObject {

    static let shared = LineManager()

    @Published var activeLine: Line

    let availableLines: [Line] = [
        Line(
            id: "BF",
            name: "Boreal Financial",
            baseURL: URL(string: APIConfig.baseURL)!,
            wsURL: nil
        ),
        Line(
            id: "BI",
            name: "Boreal Insurance",
            baseURL: URL(string: APIConfig.baseURL)!,
            wsURL: nil
        ),
        Line(
            id: "SLF",
            name: "SLF",
            baseURL: URL(string: APIConfig.baseURL)!,
            wsURL: nil
        )
    ]

    private init() {
        self.activeLine = availableLines[0]
        CallManager.shared.setActiveLine(activeLine)
    }

    func switchLine(to line: Line) {
        activeLine = line
        CallManager.shared.setActiveLine(line)
        TwilioVoiceManager.shared.disconnect()
        VoiceEngine.shared.forceTerminate()
        ConversationsService.shared.reset()

        WebSocketManager.shared.disconnect()

        Task {
            let refreshed = try? await AuthService.shared.refreshToken()
            let accessToken = refreshed ?? KeychainService.shared.load("accessToken")
            if let accessToken {
                await MainActor.run {
                    WebSocketManager.shared.connect(line: line, accessToken: accessToken)
                }
            }
        }
    }
}
