// BOREAL_DIALER_v901_WIDGET_REFRESH - the home-screen widget only got new data when the app came to the front, so it
// sat on old calls and tasks all day. iOS now wakes the app in the background (roughly every 15-30 minutes, at iOS's
// discretion) to refresh the widget's missed calls, today's count, tasks and recent calls.
import BackgroundTasks
import Foundation

enum WidgetBackgroundRefresh {
    static let identifier = "com.borealfinancial.dialer.widget-refresh"
    static let interval: TimeInterval = 15 * 60

    /// Called once from didFinishLaunching (iOS requires registration before launch finishes).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(task)
        }
    }

    /// Asks iOS for the next background refresh. Safe to call repeatedly; the newest request wins.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[widget-refresh] could not schedule: \(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule() // keep the chain going
        let work = Task {
            guard TokenStorage.shared.getToken() != nil else { task.setTaskCompleted(success: true); return }
            await DialerDashboardStore.refresh()
            _ = await WatchSnapshotSync.refresh()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
