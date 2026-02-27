import Foundation
import Combine

final class LineManager: ObservableObject {

    static let shared = LineManager()

    @Published var activeLine: Line?

    private(set) var availableLines: [Line] = []

    private init() {
        loadDefaultLines()
        activeLine = availableLines.first
    }

    private func loadDefaultLines() {
        availableLines = [
            Line(
                id: "bf",
                displayName: "Boreal Financial",
                twilioVoiceAppSid: "BF_VOICE_APP_SID",
                twilioConversationServiceSid: "BF_CONVERSATION_SID"
            )
        ]
    }

    func switchLine(to line: Line) {
        activeLine = line

        // Reset services for clean isolation
        VoiceService.shared.reset()
        ConversationsService.shared.reset()
    }
}
