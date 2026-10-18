import Foundation

// BOREAL_DIALER_v822_CARPLAY
// What each CarPlay list shows, built from the same server data as the phone's Calls tab. Kept free of the CarPlay
// framework so the rules (what is tappable, what a row says, how long a list is) are unit-tested.
struct CarPlayRow: Equatable {
    enum Action: Equatable {
        case call(phone: String)
        case callTeammate(userId: String, name: String)
        case voicemail(id: String)
        case notCallable
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let action: Action
}

enum CarPlayRows {
    /// CarPlay caps list length per vehicle; 24 is under every car's limit and plenty while driving.
    static let maxRows = 24

    static let signedOutMessage = "Open Boreal Dialer on your iPhone and sign in."
    static let noRecentsMessage = "No recent calls"
    static let noVoicemailMessage = "No voicemail"
    static let noFavouritesMessage = "Tap Favourite on a contact in Boreal Dialer to add it here."

    static func recents(_ calls: [RecentCall]) -> [CarPlayRow] {
        calls.prefix(maxRows).map { call in
            let symbol = call.missed ? "phone.down.fill"
                : (call.isInbound ? "phone.arrow.down.left" : "phone.arrow.up.right")
            let action: CarPlayRow.Action = callablePhone(call.phoneNumber).map { .call(phone: $0) } ?? .notCallable
            return CarPlayRow(id: "recent-\(call.id)", title: call.title, detail: call.subtitle,
                              symbol: symbol, action: action)
        }
    }

    static func voicemails(_ items: [Voicemail]) -> [CarPlayRow] {
        items.prefix(maxRows).map { item in
            let detail = [item.durationLabel, item.subtitle.isEmpty ? nil : item.subtitle]
                .compactMap { $0 }
                .joined(separator: " · ")
            return CarPlayRow(id: "voicemail-\(item.id)", title: item.title, detail: detail,
                              symbol: "recordingtape", action: .voicemail(id: item.id))
        }
    }

    /// Starred clients first, then the quick-call teammates.
    static func favourites(clients: [FavouriteContact], team: [QuickCallStaff]) -> [CarPlayRow] {
        let clientRows = clients.compactMap { client -> CarPlayRow? in
            guard let phone = callablePhone(client.phone) else { return nil }
            return CarPlayRow(id: "client-\(client.id)", title: client.name, detail: PhoneFormat.display(phone),
                              symbol: "star.fill", action: .call(phone: phone))
        }
        let teamRows = team.map { member in
            CarPlayRow(id: "team-\(member.userId)", title: member.displayName,
                       detail: (member.online ?? false) ? "Team · online" : "Team",
                       symbol: "person.2.fill", action: .callTeammate(userId: member.userId, name: member.displayName))
        }
        return Array((clientRows + teamRows).prefix(maxRows))
    }

    /// E.164 for a number Twilio can dial, or nil (withheld / unknown numbers are not tappable).
    static func callablePhone(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let e164 = PhoneFormat.e164(raw)
        return CommunicationSender.isE164(e164) ? e164 : nil
    }
}
