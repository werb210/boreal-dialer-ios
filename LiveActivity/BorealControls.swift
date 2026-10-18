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

// BOREAL_DIALER_v823_WIDGET_ACTIONS - three more controls for Control Center, the Lock Screen and the Action Button:
//   - "Boreal Busy": a switch; Busy sends callers to voicemail, without opening the app.
//   - "Boreal Voice Note": opens the app recording a note for your last call's client.
//   - "Boreal Next Follow-up": opens the app and calls the client on your next follow-up task.
enum BorealActionLinks {
    static let voiceNote = URL(string: "borealdialer://action/voice-note")!
    static let nextFollowUp = URL(string: "borealdialer://action/next-follow-up")!
}

@available(iOS 18.0, *)
struct BorealBusyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: StaffWidgetActionKinds.busyControl) {
            ControlWidgetToggle("Boreal Busy", isOn: StaffWidgetActionStore.isBusy, action: BorealBusyControlIntent()) { busy in
                Label(busy ? "Busy" : "Available", systemImage: busy ? "phone.down.fill" : "phone.fill")
            }
        }
        .displayName("Boreal Busy")
        .description("Busy sends Boreal callers to voicemail. Turn it off to take calls again.")
    }
}

@available(iOS 18.0, *)
struct BorealVoiceNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "financial.boreal.dialer.control.voice-note") {
            ControlWidgetButton(action: OpenURLIntent(BorealActionLinks.voiceNote)) {
                Label("Boreal Voice Note", systemImage: "mic.fill")
            }
        }
        .displayName("Boreal Voice Note")
        .description("Record a note for your last call's client. It is saved to their Boreal timeline.")
    }
}

@available(iOS 18.0, *)
struct BorealNextFollowUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "financial.boreal.dialer.control.next-follow-up") {
            ControlWidgetButton(action: OpenURLIntent(BorealActionLinks.nextFollowUp)) {
                Label("Next Follow-up", systemImage: "checklist")
            }
        }
        .displayName("Boreal Next Follow-up")
        .description("Calls the client on your next Boreal follow-up task.")
    }
}
