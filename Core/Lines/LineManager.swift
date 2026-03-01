import Foundation

@MainActor
final class LineManager: ObservableObject {

    static let shared = LineManager()

    @Published var activeLine: Line

    let availableLines: [Line] = [
        Line(
            id: "BF",
            name: "Boreal Financial",
            baseURL: URL(string: "https://bf-server.com")!,
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

        if let accessToken = KeychainService.shared.load("accessToken") {
            WebSocketManager.shared.connect(line: line, accessToken: accessToken)
        }
    }
}
