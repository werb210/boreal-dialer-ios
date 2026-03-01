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
    }

    func switchLine(to line: Line) {
        activeLine = line
        VoiceService.shared.reset()
        ConversationsService.shared.reset()
    }
}
