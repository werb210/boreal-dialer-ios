import Intents

// BOREAL_DIALER_CARPLAY_INTENTS
// iOS only lists a CarPlay communication app on the car screen (and under Settings > General > CarPlay) when the app
// ships an Intents extension that supports starting a call and searching the call history. The CarPlay permission and
// the car screen itself (Sources/CarPlay) were in build 1020, and the app still did not appear, because this was missing.
//
// The extension does no calling itself. "Call Jane with Boreal Dialer" and a tap on a Boreal call in the car's own
// Recents hand over to the app, which dials through its normal path (BorealDialerApp: onContinueUserActivity
// "INStartCallIntent"), so the call is a CallKit call from the staff member's Boreal line like any other.
final class IntentHandler: INExtension, INStartCallIntentHandling, INSearchCallHistoryIntentHandling {
    override func handler(for intent: INIntent) -> Any { self }

    // MARK: - Start a call

    func resolveContacts(for intent: INStartCallIntent) async -> [INStartCallContactResolutionResult] {
        guard let contacts = intent.contacts, !contacts.isEmpty else { return [.needsValue()] }
        return contacts.map { person in
            IntentRules.hasDialableHandle(person.personHandle?.value) ? .success(with: person) : .unsupported(forReason: .noContactFound)
        }
    }

    func resolveCallCapability(for intent: INStartCallIntent) async -> INStartCallCallCapabilityResolutionResult {
        // Boreal calls are voice calls only.
        intent.callCapability == .videoCall ? .unsupported(forReason: .videoCallUnsupported) : .success(with: .audioCall)
    }

    func handle(intent: INStartCallIntent) async -> INStartCallIntentResponse {
        INStartCallIntentResponse(code: .continueInApp, userActivity: NSUserActivity(activityType: IntentRules.startCallActivityType))
    }

    // MARK: - Call history ("show my Boreal Dialer calls")

    func handle(intent: INSearchCallHistoryIntent) async -> INSearchCallHistoryIntentResponse {
        INSearchCallHistoryIntentResponse(code: .continueInApp, userActivity: nil)
    }
}

enum IntentRules {
    /// The activity type the app already listens for (Recents, contact cards, CarPlay).
    static let startCallActivityType = "INStartCallIntent"

    /// A handle the app can dial: at least seven digits once punctuation is removed.
    static func hasDialableHandle(_ value: String?) -> Bool {
        (value ?? "").filter(\.isNumber).count >= 7
    }
}
