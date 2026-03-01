import Foundation

@MainActor
final class EventRouter {

    static let shared = EventRouter()

    private init() {}

    func route(_ event: SocketEvent) {
        switch event.type {
        case "call.incoming":
            VoiceEngine.shared.handleIncomingEvent(event.payload)
        case "call.updated":
            if event.payload.status == "failed" {
                VoiceEngine.shared.handleFailure()
            } else if event.payload.status == "ended" || event.payload.status == "completed" {
                VoiceEngine.shared.handleDisconnect()
            }
        case "sms.received":
            ConversationsService.shared.handleIncoming(event.payload)
        default:
            break
        }
    }
}
