import ActivityKit
import Foundation

final class CallLiveActivityController {
    static let shared = CallLiveActivityController()
    private init() {}
    private var activityID: String?

    func start(handle: String, line: String, status: String = "Dialing") {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let attrs = CallActivityAttributes(handle: handle, line: line)
        let state = CallActivityAttributes.ContentState(status: status, startedAt: Date())
        do {
            let activity = try Activity.request(attributes: attrs, contentState: state)
            activityID = activity.id
        } catch { activityID = nil }
    }
    func update(status: String) {
        guard #available(iOS 16.1, *), let id = activityID else { return }
        Task {
            for activity in Activity<CallActivityAttributes>.activities where activity.id == id {
                let s = CallActivityAttributes.ContentState(status: status, startedAt: activity.contentState.startedAt)
                await activity.update(using: s)
            }
        }
    }
    func end() {
        guard #available(iOS 16.1, *) else { return }
        let id = activityID; activityID = nil
        Task {
            for activity in Activity<CallActivityAttributes>.activities where (id == nil || activity.id == id) {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
