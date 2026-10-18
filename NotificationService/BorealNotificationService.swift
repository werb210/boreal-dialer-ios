import Foundation
import Intents
import UserNotifications

// BOREAL_DIALER_v822_CARPLAY
// Inbound texts and client-portal messages arrive as staff alert pushes with mutable-content. This extension attaches
// the sender as an INSendMessageIntent so iOS shows them as communication notifications: the sender's name, Siri
// reads them aloud in CarPlay / on AirPods ("Announce Notifications") and offers "Reply", which the app handles with
// SiriMessageHandler. Anything else (calls, voicemail, handoffs) passes through untouched.
final class BorealNotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var fallback: UNNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        fallback = request.content
        let content = request.content
        guard let sender = CommunicationSender.from(userInfo: content.userInfo, body: content.body,
                                                     threadId: content.threadIdentifier) else {
            deliver(content)
            return
        }
        let handle = INPersonHandle(value: sender.handle, type: sender.isPhone ? .phoneNumber : .unknown)
        let person = INPerson(personHandle: handle, nameComponents: nil, displayName: sender.displayName,
                              image: nil, contactIdentifier: nil, customIdentifier: sender.contactId,
                              isMe: false, suggestionType: .none)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText,
                                         content: sender.body, speakableGroupName: nil,
                                         conversationIdentifier: sender.conversationId, serviceName: nil,
                                         sender: person, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { [weak self] _ in
            let updated = (try? content.updating(from: intent)) ?? content
            self?.deliver(updated)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let fallback { deliver(fallback) }
    }

    /// The handler may be called once only.
    private func deliver(_ content: UNNotificationContent) {
        guard let handler = contentHandler else { return }
        contentHandler = nil
        handler(content)
    }
}
