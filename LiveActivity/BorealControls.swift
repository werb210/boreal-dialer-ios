import SwiftUI
import WidgetKit
import AppIntents

// BOREAL_DIALER_CONTROLS_v321
// Control Center and Action Button controls (iOS 18). Two buttons:
//   - "Boreal Call": opens the Boreal keypad.
//   - "Boreal Quick Call": calls the first contact in the dialer's quick-call
//     list (the same list the home-screen widget shows); opens the keypad when
//     that list is empty.
// On iPhones with an Action Button: Settings > Action Button > Controls, then
// pick either one. The Siri shortcuts (New Call, Call a Client, What's Due)
// are also offered there under Shortcut.
// Lives in the widget extension, so it only uses Sources/Shared (no networking).
enum BorealControlLinks {
    static let newCall = URL(string: "borealdialer://new-call")!

    static func quickCall(_ contacts: [WidgetContact]) -> (url: URL, name: String?) {
        guard let first = contacts.first, first.number.hasPrefix("+") else { return (newCall, nil) }
        var components = URLComponents()
        components.scheme = "borealdialer"
        components.host = "call"
        components.queryItems = [URLQueryItem(name: "phone", value: first.number), URLQueryItem(name: "start", value: "true")]
        return (components.url ?? newCall, first.name)
    }
}

@available(iOS 18.0, *)
struct BorealNewCallControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "financial.boreal.dialer.control.new-call") {
            ControlWidgetButton(action: OpenURLIntent(BorealControlLinks.newCall)) {
                Label("Boreal Call", systemImage: "phone.fill")
            }
        }
        .displayName("Boreal Call")
        .description("Opens the Boreal keypad.")
    }
}

@available(iOS 18.0, *)
struct BorealQuickCallControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "financial.boreal.dialer.control.quick-call") {
            let target = BorealControlLinks.quickCall(WidgetSnapshotStore.load().contacts)
            ControlWidgetButton(action: OpenURLIntent(target.url)) {
                Label(target.name ?? "Quick Call", systemImage: "phone.arrow.up.right.fill")
            }
        }
        .displayName("Boreal Quick Call")
        .description("Calls your first quick-call contact from your Boreal line.")
    }
}
