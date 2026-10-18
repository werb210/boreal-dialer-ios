import Foundation

// BOREAL_DIALER_v822_CARPLAY
// Clients starred on their contact card ("Favourite"). They fill the Favourites tab in CarPlay, under the three
// quick-call teammates. Kept on this phone (UserDefaults), newest first, at most 12 - CarPlay lists stay short.
struct FavouriteContact: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let phone: String
}

final class FavouriteContacts {
    static let shared = FavouriteContacts()
    static let storageKey = "boreal.v822.favouriteContacts"
    static let limit = 12
    static let didChange = Notification.Name("BorealFavouriteContactsDidChange")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var all: [FavouriteContact] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let list = try? JSONDecoder().decode([FavouriteContact].self, from: data) else { return [] }
        return list
    }

    func contains(_ id: String) -> Bool {
        all.contains { $0.id == id }
    }

    /// Adds the contact (to the top) or removes it. Returns true when it is now a favourite.
    /// A contact without a callable number cannot be a favourite: CarPlay could not call it.
    @discardableResult
    func toggle(id: String, name: String, phone: String?) -> Bool {
        var list = all
        if list.contains(where: { $0.id == id }) {
            list.removeAll { $0.id == id }
            save(list)
            return false
        }
        guard let phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        list.insert(FavouriteContact(id: id, name: name, phone: phone), at: 0)
        save(Array(list.prefix(Self.limit)))
        return true
    }

    private func save(_ list: [FavouriteContact]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Self.storageKey)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
