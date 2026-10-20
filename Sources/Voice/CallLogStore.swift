import Foundation

final class CallLogStore: ObservableObject {

    static let shared = CallLogStore()

    @Published private(set) var logs: [CallLog] = []

    private let storageKey = "call_logs"

    private init() {
        load()
    }

    /// BOREAL_DIALER_v831_DIALER_POLISH - this on-phone log (Recents reads the server) grew with every call, forever.
    static let maxLogs = 100

    func add(_ log: CallLog) {
        logs.insert(log, at: 0)
        if logs.count > Self.maxLogs { logs.removeLast(logs.count - Self.maxLogs) }
        save()
    }

    private func save() {
        if let encodedLogs = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(encodedLogs, forKey: storageKey)
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
