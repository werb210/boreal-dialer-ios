import CallKit
import Combine
import Foundation
import UIKit

@MainActor
final class CallDirectoryManager: ObservableObject {
    static let shared = CallDirectoryManager()
    static let extensionIdentifier = "com.borealfinancial.dialer.calldirectory"

    @Published private(set) var enabledStatus: CXCallDirectoryManager.EnabledStatus = .unknown

    private init() {}

    // BOREAL_DIALER_v831_DIALER_POLISH - caller ID covered only the first 200 contacts, so most callers showed as a
    // bare number when the app was closed. It now loads every contact from GET /voice/caller-directory (BF-Server
    // v831), falling back to the old 200-contact read on an older server. The full list is fetched at most every 6
    // hours (and at sign-in), not on every return to the app.
    nonisolated static let refreshInterval: TimeInterval = 6 * 3600
    private static let lastRefreshKey = "boreal.dialer.callDirectory.lastRefresh"
    private var refreshing = false

    struct DirectoryEnvelope: Decodable {
        struct Entry: Decodable { let number: String; let label: String }
        let entries: [Entry]
    }

    /// Phone number -> label, one per number; entries that aren't E.164 or have no name are skipped.
    nonisolated static func labels(from entries: [DirectoryEnvelope.Entry]) -> [Int64: String] {
        var labelsByNumber: [Int64: String] = [:]
        for entry in entries {
            guard let number = CallDirectoryStore.phoneNumber(fromE164: entry.number) else { continue }
            let label = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, labelsByNumber[number] == nil else { continue }
            labelsByNumber[number] = label
        }
        return labelsByNumber
    }

    nonisolated static func isDue(lastRefresh: Date?, now: Date = Date()) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= refreshInterval || lastRefresh > now
    }

    func refresh(force: Bool = false) async {
        guard TokenStorage.shared.getToken() != nil, !refreshing else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastRefreshKey) as? Date
        guard force || Self.isDue(lastRefresh: last) else { return }
        refreshing = true
        defer { refreshing = false }

        do {
            var labelsByNumber: [Int64: String]
            do {
                let request = try APIClient.shared.makeRequest(path: "/voice/caller-directory", silo: .bf)
                let data = try await APIClient.shared.makeAuthorizedRequest(request)
                labelsByNumber = Self.labels(from: try JSONDecoder().decode(DirectoryEnvelope.self, from: data).entries)
            } catch APIError.http(let status, _, _) where status == 404 {
                // An older BF-Server: the first 200 contacts, as before.
                let request = try APIClient.shared.makeRequest(path: "/crm/contacts?pageSize=200", silo: .bf)
                let data = try await APIClient.shared.makeAuthorizedRequest(request)
                let contacts = try JSONDecoder().decode(ContactsListEnvelope.self, from: data).data
                labelsByNumber = [:]
                for contact in contacts {
                    guard let phone = contact.callablePhone,
                          let number = CallDirectoryStore.phoneNumber(fromE164: phone) else { continue }
                    let label = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !label.isEmpty else { continue }
                    labelsByNumber[number] = label
                }
            }

            let entries = labelsByNumber.map {
                CallDirectoryEntry(phoneNumber: $0.key, label: $0.value)
            }
            // Signed out while this was loading: don't put the old account's names back.
            guard TokenStorage.shared.getToken() != nil else { return }
            try CallDirectoryStore.save(entries)
            UserDefaults.standard.set(Date(), forKey: Self.lastRefreshKey)
            try? await reloadExtension()
        } catch {
            // Caller ID is opportunistic: stale data is preferable to disrupting login or foregrounding.
            DialerEventLog.shared.record("caller_id_refresh_failed", metadata: ["error": error.localizedDescription])
        }
    }

    /// BOREAL_DIALER_LOGOUT_CLEAR_v789 - empties the caller-ID directory and
    /// reloads the extension so iOS stops labelling calls with this account's
    /// contacts.
    func clearAll() async {
        CallDirectoryStore.clear()
        UserDefaults.standard.removeObject(forKey: Self.lastRefreshKey) // BOREAL_DIALER_v831_DIALER_POLISH
        try? await reloadExtension()
    }

    func updateEnabledStatus() {
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
            withIdentifier: Self.extensionIdentifier
        ) { [weak self] status, _ in
            Task { @MainActor in self?.enabledStatus = status }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func reloadExtension() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CXCallDirectoryManager.sharedInstance.reloadExtension(
                withIdentifier: Self.extensionIdentifier
            ) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
