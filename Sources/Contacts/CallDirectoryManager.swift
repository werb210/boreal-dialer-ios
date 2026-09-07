import CallKit
import Combine
import Foundation
import UIKit

@MainActor
final class CallDirectoryManager: ObservableObject {
    static let shared = CallDirectoryManager()
    static let extensionIdentifier = "financial.boreal.dialer.calldirectory"

    @Published private(set) var enabledStatus: CXCallDirectoryManager.EnabledStatus = .unknown

    private init() {}

    func refresh() async {
        guard TokenStorage.shared.getToken() != nil else { return }

        do {
            // Reuse the CRM directory endpoint that backs ContactsView.
            let request = try APIClient.shared.makeRequest(path: "/crm/contacts?pageSize=200", silo: .bf)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let contacts = try JSONDecoder().decode(ContactsListEnvelope.self, from: data).data

            var labelsByNumber: [Int64: String] = [:]
            for contact in contacts {
                guard let phone = contact.callablePhone,
                      let number = CallDirectoryStore.phoneNumber(fromE164: phone) else { continue }
                let label = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { continue }
                labelsByNumber[number] = label
            }

            let entries = labelsByNumber.map {
                CallDirectoryEntry(phoneNumber: $0.key, label: $0.value)
            }
            try CallDirectoryStore.save(entries)
            try? await reloadExtension()
        } catch {
            // Caller ID is opportunistic: stale data is preferable to disrupting login or foregrounding.
        }
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
