import Foundation
import SwiftData
import TwilioConversationsClient

final class ConversationsService: NSObject, ObservableObject {

    static let shared = ConversationsService()

    @Published var messages: [MessageModel] = []

    var modelContext: ModelContext?

    private var client: TwilioConversationsClient?
    private var conversation: TCHConversation?

    func configureContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func initialize(for lineId: String, with token: String) {
        // token is already line-specific
        TwilioConversationsClient.conversationsClient(
            withToken: token
        ) { result, client in
            if let client = client {
                self.client = client
                client.delegate = self
            }
        }
    }

    func reset() {
        messages.removeAll()
        conversation = nil
        client = nil
    }

    func joinConversation(named name: String) {

        client?.conversation(withSidOrUniqueName: name) { result, conversation in

            if let conversation = conversation {
                self.conversation = conversation
                conversation.delegate = self
                conversation.join(completion: { _ in })
            }
        }
    }

    func sendMessage(_ text: String) {

        conversation?.sendMessage(text, completion: { result, message in
            if let message = message {
                let model = MessageModel(
                    id: message.sid ?? UUID().uuidString,
                    body: text,
                    author: "me",
                    timestamp: Date()
                )
                DispatchQueue.main.async {
                    self.messages.append(model)
                }
            }
        })
    }
}

extension ConversationsService: TwilioConversationsClientDelegate {}

extension ConversationsService: TCHConversationDelegate {

    func conversation(_ conversation: TCHConversation,
                      messageAdded message: TCHMessage) {

        let model = MessageModel(
            id: message.sid ?? UUID().uuidString,
            body: message.body ?? "",
            author: message.author ?? "",
            timestamp: message.dateCreated ?? Date()
        )

        if let line = LineManager.shared.activeLine,
           let context = modelContext {

            let stored = StoredMessage(
                id: message.sid ?? UUID().uuidString,
                lineId: line.id,
                conversationId: conversation.sid ?? "unknown",
                body: message.body ?? "",
                author: message.author ?? "",
                timestamp: message.dateCreated ?? Date()
            )

            context.insert(stored)
        }

        DispatchQueue.main.async {
            self.messages.append(model)
        }
    }
}
