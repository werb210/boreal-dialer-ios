import Foundation

@MainActor
final class LineManager: ObservableObject {

    static let shared = LineManager()

    @Published var activeLine: Line

    let availableLines: [Line] = [
        // BOREAL_DIALER_SINGLE_LINE_v1 - only the line in use. Re-add BI/SLF here
        // to restore the phone line switcher.
        Line(
            id: "BF",
            name: "Boreal Financial",
            baseURL: URL(string: APIConfig.BASE_URL)!,
            wsURL: nil,
            silo: .bf
        )
    ]

    private init() {
        let savedSilo = UserDefaults.standard.string(forKey: "activeSilo")
            .flatMap(Silo.init(rawValue:)) ?? .bf
        let initialLine = availableLines.first(where: { $0.silo == savedSilo }) ?? availableLines[0]

        self.activeLine = initialLine
        APIConfig.activeBaseURL = APIConfig.url(for: initialLine.silo)
        // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - APIClient reads this for X-Silo.
        APIConfig.activeSilo = initialLine.silo
        CallManager.shared.setActiveLine(initialLine)
    }

    func switchLine(to line: Line) {
        guard activeLine != line else { return }
        activeLine = line

        // Update the global API base URL for this silo
        APIConfig.activeBaseURL = APIConfig.url(for: line.silo)
        APIConfig.activeSilo = line.silo

        // Persist the active silo selection
        UserDefaults.standard.set(line.silo.rawValue, forKey: "activeSilo")

        // Notify all services that the silo has changed
        NotificationCenter.default.post(name: .siloDidChange, object: line.silo)

        CallManager.shared.setActiveLine(line)
        TwilioVoiceManager.shared.disconnect()
        VoiceEngine.shared.forceTerminate()

        // Re-register for Twilio voice with the new silo's token
        Task {
            await VoiceManager.shared.reinitialize()
        }
    }
}
