import Foundation

// BOREAL_DIALER_v823_ACTIONS
// borealdialer://action/<name> links from the Control Center controls, the Action Button and Siri:
//   action/voice-note      - record a note for the last call's client (VoiceNoteSheet)
//   action/next-follow-up  - call the client on the next follow-up task
// Kept apart from the call links (DialerDeepLinkParser) so their strict rules stay as they are.
enum StaffActionLink: String, Equatable, Identifiable {
    case voiceNote = "voice-note"
    case nextFollowUp = "next-follow-up"

    var id: String { rawValue }

    static func parse(_ url: URL) -> StaffActionLink? {
        guard url.scheme?.lowercased() == "borealdialer",
              url.host?.lowercased() == "action",
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 1 else { return nil }
        return StaffActionLink(rawValue: String(parts[0]).lowercased())
    }
}

@MainActor
final class StaffActionRouter: ObservableObject {
    static let shared = StaffActionRouter()

    /// The voice-note sheet RootTabView presents.
    @Published var voiceNote: VoiceNoteTarget?
    @Published var message: String?

    private init() {}

    /// True when the URL was an action link (handled or not).
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let link = StaffActionLink.parse(url) else { return false }
        Task { await self.run(link) }
        return true
    }

    func run(_ link: StaffActionLink) async {
        guard TokenStorage.shared.getToken() != nil else { return }
        switch link {
        case .voiceNote:
            voiceNote = await VoiceNoteTarget.lastCallClient() ?? VoiceNoteTarget(contactId: nil, name: nil)
        case .nextFollowUp:
            await callNextFollowUp()
        }
    }

    private func callNextFollowUp() async {
        do {
            let followUp = try await StaffBriefing.fetchNextFollowUp()
            switch StaffBriefing.followUpAction(followUp) {
            case .explain(let text):
                message = text
            case .call(let phone, _):
                guard let url = BorealClientLookup.callURL(phone: phone), DeepLinkCoordinator.shared.receive(url) else {
                    message = "Finish your current call first."
                    return
                }
            }
        } catch {
            message = "Couldn't reach Boreal right now."
        }
    }
}
