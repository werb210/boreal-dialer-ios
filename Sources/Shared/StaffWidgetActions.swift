import Foundation
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

// BOREAL_DIALER_v823_WIDGET_ACTIONS
// One-tap actions from the home-screen widget and Control Center, without opening the app:
//   - Available / Busy (POST /telephony/presence, the same switch as the portal's topbar)
//   - tick a task done (POST /tasks/:id/complete)
// The intents are LiveActivityIntents, so iOS runs them in the app's process (the extension has no sign-in or
// networking). The app installs the handler at launch; if it is not there yet the action waits in the App Group and
// the app applies it the next time it comes to the front. Compiled into the app and the widget extension.
enum StaffWidgetAction: Codable, Equatable {
    case setBusy(Bool)
    case completeTask(id: String)
}

enum StaffWidgetActionStore {
    private static let pendingKey = "widget.pendingActions.v823"
    private static let busyKey = "widget.presenceBusy.v823"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroup) }

    /// What the widget and the Control Center toggle show (the app writes it after every change).
    static var isBusy: Bool {
        get { defaults?.bool(forKey: busyKey) ?? false }
        set {
            defaults?.set(newValue, forKey: busyKey)
            reloadSurfaces()
        }
    }

    static func enqueue(_ action: StaffWidgetAction) {
        var list = pending()
        list.removeAll { existing in
            // A newer Busy/Available choice replaces an older one; a task is completed once.
            switch (existing, action) {
            case (.setBusy, .setBusy): return true
            default: return existing == action
            }
        }
        list.append(action)
        if let data = try? JSONEncoder().encode(list) { defaults?.set(data, forKey: pendingKey) }
    }

    static func pending() -> [StaffWidgetAction] {
        guard let data = defaults?.data(forKey: pendingKey),
              let list = try? JSONDecoder().decode([StaffWidgetAction].self, from: data) else { return [] }
        return list
    }

    static func takePending() -> [StaffWidgetAction] {
        let list = pending()
        defaults?.removeObject(forKey: pendingKey)
        return list
    }

    static func clear() {
        defaults?.removeObject(forKey: pendingKey)
        defaults?.removeObject(forKey: busyKey)
        reloadSurfaces()
    }

    static func reloadSurfaces() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "BorealDialerWidget")
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: StaffWidgetActionKinds.busyControl)
        }
#endif
    }
}

enum StaffWidgetActionKinds {
    static let busyControl = "financial.boreal.dialer.control.busy"
}

/// Set by the app at launch. Nil inside the widget extension.
enum StaffWidgetActionBridge {
    static var handler: ((StaffWidgetAction) async -> Void)?

    static func run(_ action: StaffWidgetAction) async {
        if case .setBusy(let busy) = action { StaffWidgetActionStore.isBusy = busy } // instant feedback on the widget
        if let handler {
            await handler(action)
        } else {
            StaffWidgetActionStore.enqueue(action)
        }
    }
}

#if canImport(AppIntents)
@available(iOS 17.0, *)
struct SetBorealBusyIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Boreal Busy or Available"
    static var description = IntentDescription("Marks you Busy (calls go to voicemail) or Available on your Boreal line.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Busy")
    var busy: Bool

    init() {}
    init(busy: Bool) { self.busy = busy }

    func perform() async throws -> some IntentResult {
        await StaffWidgetActionBridge.run(.setBusy(busy))
        return .result()
    }
}

@available(iOS 17.0, *)
struct CompleteBorealTaskIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete a Boreal Task"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task")
    var taskId: String

    init() {}
    init(taskId: String) { self.taskId = taskId }

    func perform() async throws -> some IntentResult {
        guard !taskId.isEmpty else { return .result() }
        await StaffWidgetActionBridge.run(.completeTask(id: taskId))
        return .result()
    }
}

/// The Control Center / Action Button toggle (iOS 18).
@available(iOS 18.0, *)
struct BorealBusyControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Boreal Busy"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Busy")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        await StaffWidgetActionBridge.run(.setBusy(value))
        return .result()
    }
}
#endif
