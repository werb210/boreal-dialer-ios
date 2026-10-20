import CarPlay
import Combine
import Foundation
import UIKit

// BOREAL_DIALER_v822_CARPLAY
// Boreal Dialer on the car screen (CarPlay Communication App entitlement, granted Oct 17 2026). Three tabs:
//   Recents    - the server call log; tap a call to call the number back.
//   Favourites - clients starred on their contact card, then the three quick-call teammates; tap to call.
//   Voicemail  - tap for Play / Call back; audio plays through the car.
// Calls themselves are CallKit calls, so the car shows its own in-call screen and incoming Boreal calls ring on it
// like any phone call. Texts are read aloud by Siri (communication notifications - see BorealNotificationService).
// Info.plist routes the CarPlay scene role here (UIApplicationSceneManifest in project.yml).
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        Task { @MainActor in CarPlayController.shared.connect(interfaceController) }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        Task { @MainActor in CarPlayController.shared.disconnect() }
    }
}

@MainActor
final class CarPlayController: NSObject, CPTabBarTemplateDelegate {
    static let shared = CarPlayController()

    private weak var interface: CPInterfaceController?
    private let recentsTemplate = CPListTemplate(title: "Recents", sections: [])
    private let favouritesTemplate = CPListTemplate(title: "Favourites", sections: [])
    private let voicemailTemplate = CPListTemplate(title: "Voicemail", sections: [])
    private let recentsModel = RecentCallsViewModel()
    private let voicemailModel = VoicemailViewModel()
    private let quickCallModel = QuickCallViewModel()
    private var observers: Set<AnyCancellable> = []
    private var refreshTimer: Timer?

    private override init() {
        super.init()
        recentsTemplate.tabImage = UIImage(systemName: "clock.fill")
        favouritesTemplate.tabImage = UIImage(systemName: "star.fill")
        voicemailTemplate.tabImage = UIImage(systemName: "recordingtape")
    }

    func connect(_ interface: CPInterfaceController) {
        self.interface = interface
        let tabs = CPTabBarTemplate(templates: [recentsTemplate, favouritesTemplate, voicemailTemplate])
        tabs.delegate = self
        interface.setRootTemplate(tabs, animated: false, completion: nil)
        observe()
        refreshAll()
        // A missed call or new voicemail shows up within a minute while driving.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in CarPlayController.shared.refreshAll() }
        }
    }

    func disconnect() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        observers.removeAll()
        voicemailModel.stop()
        interface = nil
    }

    nonisolated func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        Task { @MainActor in CarPlayController.shared.refreshAll() }
    }

    // MARK: - Data

    private var signedIn: Bool { TokenStorage.shared.getToken() != nil }

    private func observe() {
        observers.removeAll()
        // The playing indicator follows the voicemail player; a finished call refreshes Recents.
        voicemailModel.$playingId
            .receive(on: RunLoop.main)
            .sink { _ in Task { @MainActor in CarPlayController.shared.renderVoicemail() } }
            .store(in: &observers)
        VoiceEngine.shared.$state
            .map { state -> Bool in if case .idle = state { return true } else { return false } }
            .removeDuplicates()
            .filter { $0 }
            .dropFirst()
            .sink { _ in Task { @MainActor in CarPlayController.shared.refreshAll() } }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: FavouriteContacts.didChange)
            .sink { _ in Task { @MainActor in CarPlayController.shared.renderFavourites() } }
            .store(in: &observers)
    }

    func refreshAll() {
        guard interface != nil else { return }
        guard signedIn else {
            for template in [recentsTemplate, favouritesTemplate, voicemailTemplate] {
                template.emptyViewTitleVariants = [CarPlayRows.signedOutMessage]
                template.updateSections([])
            }
            return
        }
        Task {
            await recentsModel.load()
            renderRecents()
        }
        Task {
            await voicemailModel.load()
            renderVoicemail()
        }
        Task {
            await quickCallModel.load()
            renderFavourites()
        }
    }

    // MARK: - Lists

    private func renderRecents() {
        recentsTemplate.emptyViewTitleVariants = [recentsModel.error ?? CarPlayRows.noRecentsMessage]
        recentsTemplate.updateSections([CPListSection(items: CarPlayRows.recents(recentsModel.calls).map(item))])
    }

    func renderVoicemail() {
        voicemailTemplate.emptyViewTitleVariants = [voicemailModel.error ?? CarPlayRows.noVoicemailMessage]
        let items = CarPlayRows.voicemails(voicemailModel.voicemails).map { row -> CPListItem in
            let listItem = item(row)
            if case .voicemail(let id) = row.action, voicemailModel.playingId == id {
                listItem.isPlaying = true
                listItem.playingIndicatorLocation = .trailing
            }
            return listItem
        }
        voicemailTemplate.updateSections([CPListSection(items: items)])
    }

    func renderFavourites() {
        guard signedIn else { return }
        favouritesTemplate.emptyViewTitleVariants = [CarPlayRows.noFavouritesMessage]
        let rows = CarPlayRows.favourites(clients: FavouriteContacts.shared.all, team: quickCallModel.pinned)
        favouritesTemplate.updateSections([CPListSection(items: rows.map(item))])
    }

    private func item(_ row: CarPlayRow) -> CPListItem {
        let listItem = CPListItem(text: row.title, detailText: row.detail.isEmpty ? nil : row.detail,
                                  image: UIImage(systemName: row.symbol))
        listItem.userInfo = row.id
        if row.action == .notCallable {
            listItem.isEnabled = false
        } else {
            listItem.handler = { _, completion in
                Task { @MainActor in
                    CarPlayController.shared.perform(row.action)
                    completion()
                }
            }
        }
        return listItem
    }

    // MARK: - Actions

    private func perform(_ action: CarPlayRow.Action) {
        switch action {
        case .call(let phone):
            guard readyToCall() else { return }
            CallManager.shared.startCall(to: phone)
        case .callTeammate(let userId, let name):
            guard readyToCall() else { return }
            VoiceEngine.shared.startInternalCall(staffIdentity: userId, displayName: name)
        case .voicemail(let id):
            guard let voicemail = voicemailModel.voicemails.first(where: { $0.id == id }) else { return }
            presentVoicemailActions(voicemail)
        case .notCallable:
            break
        }
    }

    private func readyToCall() -> Bool {
        guard signedIn else {
            alert(CarPlayRows.signedOutMessage)
            return false
        }
        guard !VoiceEngine.shared.isOnCall else { // BOREAL_DIALER_v831_DIALER_POLISH - not refused in the pause after a call
            alert("Finish your current call first.")
            return false
        }
        voicemailModel.stop()
        return true
    }

    private func presentVoicemailActions(_ voicemail: Voicemail) {
        let playing = voicemailModel.playingId == voicemail.id
        var actions = [
            CPAlertAction(title: playing ? "Stop" : "Play", style: .default) { _ in
                Task { @MainActor in
                    CarPlayController.shared.dismissPresented()
                    await CarPlayController.shared.voicemailModel.play(voicemail)
                    CarPlayController.shared.renderVoicemail()
                }
            }
        ]
        if let phone = CarPlayRows.callablePhone(voicemail.contactPhone) {
            actions.append(CPAlertAction(title: "Call back", style: .default) { _ in
                Task { @MainActor in
                    CarPlayController.shared.dismissPresented()
                    CarPlayController.shared.perform(.call(phone: phone))
                }
            })
        }
        actions.append(CPAlertAction(title: "Cancel", style: .cancel) { _ in
            Task { @MainActor in CarPlayController.shared.dismissPresented() }
        })
        let detail = [voicemail.durationLabel, voicemail.subtitle.isEmpty ? nil : voicemail.subtitle]
            .compactMap { $0 }
            .joined(separator: " · ")
        let sheet = CPActionSheetTemplate(title: voicemail.title, message: detail.isEmpty ? nil : detail, actions: actions)
        interface?.presentTemplate(sheet, animated: true, completion: nil)
    }

    private func alert(_ message: String) {
        let ok = CPAlertAction(title: "OK", style: .cancel) { _ in
            Task { @MainActor in CarPlayController.shared.dismissPresented() }
        }
        interface?.presentTemplate(CPAlertTemplate(titleVariants: [message], actions: [ok]), animated: true, completion: nil)
    }

    private func dismissPresented() {
        guard interface?.presentedTemplate != nil else { return }
        interface?.dismissTemplate(animated: true, completion: nil)
    }
}
