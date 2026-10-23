import Foundation

// BOREAL_DIALER_CONTACTS_SILO_v39 - Hashable for the Contacts picker.
enum Silo: String, Codable, Hashable, CaseIterable {
    case bf
    case bi
    case slf
    case ks // DIALER_v850_KS_CRM - Keystone
}
