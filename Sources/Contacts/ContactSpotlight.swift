import Foundation
#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
#endif

// BOREAL_DIALER_v593_SPOTLIGHT
enum ContactSpotlight {
    static let domain = "financial.boreal.dialer.contacts"
    static let prefix = "boreal.contact|"

    static func identifier(phone: String, id: String) -> String { prefix + phone + "|" + id }

    static func phone(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let parts = identifier.dropFirst(prefix.count).split(separator: "|", maxSplits: 1)
        guard let first = parts.first, first.hasPrefix("+") else { return nil }
        return String(first)
    }

    static func callURL(phone: String) -> URL? {
        var components = URLComponents()
        components.scheme = "borealdialer"
        components.host = "call"
        components.queryItems = [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "start", value: "false")]
        return components.url
    }

    static func index(_ contacts: [CRMContact]) {
        #if canImport(CoreSpotlight)
        let items: [CSSearchableItem] = contacts.prefix(500).compactMap { contact in
            guard let phone = BorealClientLookup.e164(contact.callablePhone) else { return nil }
            let attributes = CSSearchableItemAttributeSet(contentType: .contact)
            attributes.title = contact.displayName
            attributes.contentDescription = [contact.companyName, phone].compactMap { $0 }.joined(separator: " · ")
            attributes.phoneNumbers = [phone]
            attributes.supportsPhoneCall = true
            return CSSearchableItem(uniqueIdentifier: identifier(phone: phone, id: contact.id), domainIdentifier: domain, attributeSet: attributes)
        }
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error { print("[spotlight] index failed: \(error.localizedDescription)") }
        }
        #endif
    }

    static func clear() {
        #if canImport(CoreSpotlight)
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
        #endif
    }
}
