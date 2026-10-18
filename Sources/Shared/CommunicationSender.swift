import Foundation

// BOREAL_DIALER_v822_CARPLAY
// Who sent an inbound text or client-portal message, read from the staff alert push (BF-Server v822 adds
// "mutable-content" and "senderName" to SMS and CLIENT_MESSAGE alerts). The notification service extension turns it
// into an INSendMessageIntent, which makes the alert a "communication notification": Siri reads it aloud in CarPlay
// and on AirPods and offers to reply. Foundation only - compiled into the app (tests) and the extension.
struct CommunicationSender: Equatable {
    let displayName: String
    /// E.164 number when the push carried one; otherwise "boreal-contact:<id>".
    let handle: String
    let isPhone: Bool
    let contactId: String?
    let conversationId: String
    let body: String

    static let messageTypes: Set<String> = ["sms", "client_message"]
    static let contactHandlePrefix = "boreal-contact:"

    static func from(userInfo: [AnyHashable: Any], body: String, threadId: String) -> CommunicationSender? {
        guard let type = userInfo["type"] as? String, messageTypes.contains(type) else { return nil }
        let phone = (userInfo["phone"] as? String).flatMap { isE164($0) ? $0 : nil }
        let contactId = (userInfo["contactId"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let name = (userInfo["senderName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let display = (name?.isEmpty == false ? name : nil) ?? phone.map(displayPhone) ?? "Boreal client"
        let handle: String
        if let phone {
            handle = phone
        } else if let contactId {
            handle = contactHandlePrefix + contactId
        } else {
            return nil
        }
        let conversation = threadId.isEmpty ? "\(type):\(contactId ?? phone ?? "general")" : threadId
        return CommunicationSender(displayName: display, handle: handle, isPhone: phone != nil,
                                   contactId: contactId, conversationId: conversation, body: body)
    }

    /// The contact id a "boreal-contact:<id>" handle names (Siri hands the handle back on a reply).
    static func contactId(fromHandle handle: String?) -> String? {
        guard let handle, handle.hasPrefix(contactHandlePrefix) else { return nil }
        let id = String(handle.dropFirst(contactHandlePrefix.count))
        return id.isEmpty ? nil : id
    }

    static func isE164(_ value: String) -> Bool {
        value.range(of: "^\\+[1-9][0-9]{7,14}$", options: .regularExpression) != nil
    }

    /// "+17809167413" -> "(780) 916-7413"; anything else is returned unchanged.
    static func displayPhone(_ e164: String) -> String {
        let digits = e164.filter { $0.isNumber }
        guard digits.count == 11, digits.hasPrefix("1") else { return e164 }
        let d = Array(digits.dropFirst())
        return "(\(String(d[0..<3]))) \(String(d[3..<6]))-\(String(d[6..<10]))"
    }
}
