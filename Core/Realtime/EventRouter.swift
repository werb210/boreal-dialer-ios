import Foundation

@MainActor
final class EventRouter {

    static let shared = EventRouter()

    private init() {}

    func route(_ event: SocketEvent) {
        switch event.type {
        case "call.incoming":
            VoiceService.shared.handleIncoming(event.payload)
        case "call.updated":
            VoiceService.shared.handleUpdate(event.payload)
        case "sms.received":
            ConversationsService.shared.handleIncoming(event.payload)
        default:
            break
        }
    }
}
