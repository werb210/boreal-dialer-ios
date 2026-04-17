import Foundation

@MainActor
final class LineManager: ObservableObject {

    static let shared = LineManager()

    @Published var activeLine: Line

    let availableLines: [Line] = [
        Line(
            id: "BF",
            name: "Boreal Financial",
            baseURL: URL(string: APIConfig.BASE_URL)!,
            wsURL: nil,
            silo: .bf
        ),
        Line(
            id: "BI",
            name: "Boreal Insurance",
            baseURL: URL(string: APIConfig.BASE_URL)!,
            wsURL: nil,
            silo: .bi
        ),
        Line(
            id: "SLF",
            name: "Site Level Financial",
            baseURL: URL(string: APIConfig.BASE_URL)!,
            wsURL: nil,
            silo: .slf
        )
    ]

    private init() {
        let savedSilo = UserDefaults.standard.string(forKey: "activeSilo")
            .flatMap(Silo.init(rawValue:)) ?? .bf
        let initialLine = availableLines.first(where: { $0.silo == savedSilo }) ?? availableLines[0]

        self.activeLine = initialLine
        APIConfig.activeBaseURL = APIConfig.url(for: initialLine.silo)
        CallManager.shared.setActiveLine(initialLine)
    }

    func switchLine(to line: Line) {
        guard activeLine != line else { return }
        activeLine = line

        // Update the global API base URL for this silo
        APIConfig.activeBaseURL = APIConfig.url(for: line.silo)

        // Persist the active silo selection
        UserDefaults.standard.set(line.silo.rawValue, forKey: "activeSilo")

        // Notify all services that the silo has changed
        NotificationCenter.default.post(name: .siloDidChange, object: line.silo)

        CallManager.shared.setActiveLine(line)
        TwilioVoiceManager.shared.disconnect()
        VoiceEngine.shared.forceTerminate()
        ConversationsService.shared.reset()

        // Re-register for Twilio voice with the new silo's token
        Task {
            await VoiceManager.shared.reinitialize()
        }
    }
}
