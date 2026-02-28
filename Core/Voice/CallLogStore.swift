import Foundation

final class CallLogStore: ObservableObject {

    static let shared = CallLogStore()

    @Published private(set) var logs: [CallLog] = []

    private let storageKey = "boreal.call.logs"

    private init() {
        load()
    }

    func add(_ log: CallLog) {
        logs.insert(log, at: 0)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([CallLog].self, from: data)
        else { return }

        logs = decoded
    }
}
