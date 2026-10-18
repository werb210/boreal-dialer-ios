import Foundation

// BOREAL_DIALER_v823_WIDGET_ACTIONS
// The app side of the widget / Control Center buttons (StaffWidgetActions.swift) and of the Account sheet's
// Busy switch:
//   Busy / Available -> POST /api/telephony/presence {status: "busy" | "available"} (the portal topbar's switch;
//                       Busy sends callers to voicemail)
//   Task done        -> POST /api/tasks/:id/complete, then the task leaves the large widget.
@MainActor
final class StaffQuickActions: ObservableObject {
    static let shared = StaffQuickActions()

    @Published private(set) var isBusy = StaffWidgetActionStore.isBusy
    @Published var error: String?

    private init() {}

    /// Called once from BorealDialerApp.init.
    func install() {
        StaffWidgetActionBridge.handler = { action in
            await StaffQuickActions.shared.perform(action)
        }
    }

    /// Anything tapped while the app could not run it (e.g. before it had launched).
    func applyPending() async {
        for action in StaffWidgetActionStore.takePending() {
            await perform(action)
        }
    }

    func perform(_ action: StaffWidgetAction) async {
        guard TokenStorage.shared.getToken() != nil else { return }
        switch action {
        case .setBusy(let busy):
            await setBusy(busy)
        case .completeTask(let id):
            await completeTask(id: id)
        }
    }

    func setBusy(_ busy: Bool) async {
        let previous = isBusy
        isBusy = busy
        StaffWidgetActionStore.isBusy = busy
        do {
            let body = try JSONSerialization.data(withJSONObject: ["status": Self.presenceStatus(busy: busy)])
            let request = try APIClient.shared.makeRequest(path: "/telephony/presence", method: "POST", body: body)
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
            error = nil
        } catch {
            isBusy = previous
            StaffWidgetActionStore.isBusy = previous
            self.error = "Couldn't change your status. Try again."
        }
    }

    func completeTask(id: String) async {
        guard let path = Self.completePath(taskId: id) else { return }
        // Off the widget straight away; it comes back on the next refresh if the server refused.
        var dashboard = DialerDashboardStore.load()
        dashboard.tasks.removeAll { $0.taskId == id }
        DialerDashboardStore.save(dashboard)
        if let request = try? APIClient.shared.makeRequest(path: path, method: "POST", body: Data("{}".utf8)) {
            _ = try? await APIClient.shared.makeAuthorizedRequest(request)
        }
        await DialerDashboardStore.refresh()
    }

    // MARK: - Rules (unit-tested)

    static func presenceStatus(busy: Bool) -> String { busy ? "busy" : "available" }

    static func completePath(taskId: String) -> String? {
        let trimmed = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
              trimmed.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else { return nil }
        return "/tasks/\(trimmed)/complete"
    }
}
