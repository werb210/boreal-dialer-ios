import Foundation
import Intents

// BOREAL_DIALER_v822_CARPLAY
// SiriKit messaging, handled inside the app (INIntentsSupported in Info.plist, DialerAppDelegate.handlerFor):
//   "Hey Siri, send a message to Jane with Boreal Dialer" - and "Reply" after Siri reads an inbound text in CarPlay.
// The text goes out from the staff member's Boreal line through POST /api/sms/send, exactly like the app's composer.
// A reply to a text arrives with the sender's number as the handle (set by BorealNotificationService); a name is looked
// up in Boreal CRM.
final class SiriMessageHandler: NSObject, INSendMessageIntentHandling {
    static let shared = SiriMessageHandler()

    struct Target: Equatable {
        let phone: String
        let name: String
        let contactId: String?
    }

    // MARK: - Resolve

    func resolveRecipients(for intent: INSendMessageIntent) async -> [INSendMessageRecipientResolutionResult] {
        guard let recipients = intent.recipients, !recipients.isEmpty else {
            return [INSendMessageRecipientResolutionResult(personResolutionResult: .needsValue())]
        }
        // Boreal sends one text at a time; a group message is not something the Boreal line can do.
        guard recipients.count == 1, let recipient = recipients.first else {
            return [INSendMessageRecipientResolutionResult.unsupported(forReason: .noValidHandle)]
        }
        if let target = Self.directTarget(recipient) {
            return [INSendMessageRecipientResolutionResult(personResolutionResult: .success(with: Self.person(target)))]
        }
        let wanted = recipient.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, TokenStorage.shared.getToken() != nil else {
            return [INSendMessageRecipientResolutionResult(personResolutionResult: .needsValue())]
        }
        let matches = (try? await BorealClientLookup.search(wanted)) ?? []
        let targets = Self.targets(from: matches, preferring: CommunicationSender.contactId(fromHandle: recipient.personHandle?.value)
                                                    ?? recipient.customIdentifier)
        switch targets.count {
        case 0:
            return [INSendMessageRecipientResolutionResult.unsupported(forReason: .noAccount)]
        case 1:
            return [INSendMessageRecipientResolutionResult(personResolutionResult: .success(with: Self.person(targets[0])))]
        default:
            return [INSendMessageRecipientResolutionResult(personResolutionResult: .disambiguation(with: targets.prefix(5).map(Self.person)))]
        }
    }

    func resolveContent(for intent: INSendMessageIntent) async -> INStringResolutionResult {
        let text = (intent.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .needsValue() : .success(with: text)
    }

    // MARK: - Send

    func handle(intent: INSendMessageIntent) async -> INSendMessageIntentResponse {
        guard TokenStorage.shared.getToken() != nil else {
            return INSendMessageIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil)
        }
        let body = (intent.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let recipient = intent.recipients?.first, let target = Self.directTarget(recipient) else {
            return INSendMessageIntentResponse(code: .failure, userActivity: nil)
        }
        do {
            try await API.sendSMS(SendSMSPayload(to: target.phone, body: body, contactId: target.contactId))
            return INSendMessageIntentResponse(code: .success, userActivity: nil)
        } catch {
            return INSendMessageIntentResponse(code: .failure, userActivity: nil)
        }
    }

    // MARK: - Rules (unit-tested)

    /// A recipient that already carries a dialable number (a reply, or a person Siri resolved through us).
    static func directTarget(_ person: INPerson) -> Target? {
        guard let value = person.personHandle?.value else { return nil }
        let phone = PhoneFormat.e164(value)
        guard CommunicationSender.isE164(phone) else { return nil }
        let name = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Target(phone: phone, name: name.isEmpty ? PhoneFormat.display(phone) : name,
                      contactId: person.customIdentifier)
    }

    /// CRM matches that have a mobile number; the contact the reply names comes first and alone when present.
    static func targets(from contacts: [CRMContact], preferring contactId: String?) -> [Target] {
        let callable = contacts.compactMap { contact -> Target? in
            guard let phone = BorealClientLookup.e164(contact.callablePhone) else { return nil }
            return Target(phone: phone, name: contact.displayName, contactId: contact.id)
        }
        if let contactId, let exact = callable.first(where: { $0.contactId == contactId }) {
            return [exact]
        }
        return callable
    }

    static func person(_ target: Target) -> INPerson {
        INPerson(personHandle: INPersonHandle(value: target.phone, type: .phoneNumber), nameComponents: nil,
                 displayName: target.name, image: nil, contactIdentifier: nil, customIdentifier: target.contactId)
    }

    /// Siri asks once, the first time the signed-in app comes to the front.
    static func requestAuthorizationIfNeeded() {
        guard INPreferences.siriAuthorizationStatus() == .notDetermined else { return }
        INPreferences.requestSiriAuthorization { _ in }
    }
}
