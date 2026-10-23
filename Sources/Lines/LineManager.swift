import Foundation

@MainActor
final class LineManager: ObservableObject {

    static let shared = LineManager()

    @Published var activeLine: Line

    // DIALER_v850_KS_CRM - the base lines; availableLines adds Keystone for Admin and Marketing staff.
    private let baseLines: [Line] = [
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

    // DIALER_v850_KS_CRM - read on each use, so it follows whoever is signed in.
    var availableLines: [Line] {
        KeystoneAccess.lines(base: baseLines, role: KeystoneAccess.currentRole())
    }

    private init() {
        let savedSilo = UserDefaults.standard.string(forKey: "activeSilo")
            .flatMap(Silo.init(rawValue:)) ?? .bf
        // DIALER_v850_KS_CRM - a saved Keystone line only comes back for a sign-in that may use it.
        let lines = KeystoneAccess.lines(base: baseLines, role: KeystoneAccess.currentRole())
        let initialLine = lines.first(where: { $0.silo == savedSilo }) ?? lines[0]

        self.activeLine = initialLine
        APIConfig.activeBaseURL = APIConfig.url(for: initialLine.silo)
        // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - APIClient reads this for X-Silo.
        APIConfig.activeSilo = initialLine.silo
        CallManager.shared.setActiveLine(initialLine)
    }

    // DIALER_v850_KS_CRM - a Keystone line picked by an Admin/Marketing sign-in does not carry over to a sign-in
    // that may not use it: the line goes back to BF (never mid-call).
    func enforceAccess() {
        let lines = availableLines
        guard !lines.contains(activeLine), let fallback = lines.first, !VoiceEngine.shared.isOnCall else { return }
        switchLine(to: fallback)
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
