import Foundation
import TwilioConversationsClient

struct QueuedMessage: Codable {
    let id: String
    let body: String
    let number: String
    let direction: String
    let timestamp: Date
    let lineId: String
}

final class ConversationsService: NSObject, ObservableObject {

    static let shared = ConversationsService()

    @Published var messages: [MessageModel] = []

    private var client: TwilioConversationsClient?
    private var conversation: TCHConversation?
    private let queueStorageKey = "boreal.sms.queue"
    private var queuedMessages: [QueuedMessage] = []

    override init() {
        super.init()
        loadQueue()
    }

    func initialize(for lineId: String, with token: String) {
        TwilioConversationsClient.conversationsClient(withToken: token) { _, client in
            if let client {
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

        client?.conversation(withSidOrUniqueName: name) { _, conversation in

            if let conversation {
                self.conversation = conversation
                conversation.delegate = self
                conversation.join(completion: { _ in })
            }
        }
    }

    func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        let line = LineManager.shared.activeLine
        let number = "unknown"

        if !ReachabilityManager.shared.isOnline {
            queueMessage(body: text, number: number, lineId: line.id)
            return
        }

        conversation?.sendMessage(text, completion: { _, message in
            if let message {
                let model = MessageModel(
                    id: message.sid ?? UUID().uuidString,
                    body: text,
                    author: "me",
                    timestamp: Date()
                )
                self.persistMessage(
                    id: model.id,
                    body: text,
                    number: number,
                    direction: "outbound",
                    timestamp: model.timestamp,
                    lineId: line.id
                )
                DispatchQueue.main.async {
                    self.messages.append(model)
                }
            }
        })
    }


    func handleIncoming(_ payload: DataContainer) {
        guard let number = payload.number,
              let body = payload.body else { return }

        let message = MessageModel(
            id: payload.id ?? UUID().uuidString,
            body: body,
            author: number,
            timestamp: payload.timestamp ?? Date()
        )

        persist(message)
        messages.append(message)
    }

    func retryQueuedMessages() {
        guard ReachabilityManager.shared.isOnline else { return }
        let pending = queuedMessages
        queuedMessages.removeAll()
        saveQueue()

        for message in pending {
            sendMessage(message.body)
        }
    }


    private func persist(_ message: MessageModel) {
        let line = LineManager.shared.activeLine
        persistMessage(
            id: message.id,
            body: message.body,
            number: message.author,
            direction: "inbound",
            timestamp: message.timestamp,
            lineId: line.id
        )
    }

    private func queueMessage(body: String, number: String, lineId: String) {
        let queued = QueuedMessage(
            id: UUID().uuidString,
            body: body,
            number: number,
            direction: "outbound",
            timestamp: Date(),
            lineId: lineId
        )
        queuedMessages.append(queued)
        saveQueue()
        persistMessage(
            id: queued.id,
            body: queued.body,
            number: queued.number,
            direction: queued.direction,
            timestamp: queued.timestamp,
            lineId: queued.lineId
        )
    }

    private func persistMessage(id: String,
                                body: String,
                                number: String,
                                direction: String,
                                timestamp: Date,
                                lineId: String) {
        let context = PersistenceController.shared.container.viewContext
        let entity = MessageEntity(context: context)
        entity.id = id
        entity.body = body
        entity.number = number
        entity.direction = direction
        entity.timestamp = timestamp
        entity.lineId = lineId
        try? context.save()
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queuedMessages) {
            UserDefaults.standard.set(data, forKey: queueStorageKey)
        }
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueStorageKey),
              let decoded = try? JSONDecoder().decode([QueuedMessage].self, from: data)
        else { return }
        queuedMessages = decoded
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

        let line = LineManager.shared.activeLine
        persistMessage(
            id: model.id,
            body: model.body,
            number: message.author ?? "unknown",
            direction: "inbound",
            timestamp: model.timestamp,
            lineId: line.id
        )

        DispatchQueue.main.async {
            self.messages.append(model)
        }
    }
}
