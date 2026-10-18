// BOREAL_DIALER_LARGE_WIDGET_v685 - fills the large widget: recent calls (missed ones and
// today's count) and today's tasks, fetched when the app comes to the front.
import Foundation

private struct DashCall: Decodable {
    let direction: String?
    let status: String?
    let created_at: String?
    let phone_number: String?
    let contact_name: String?
}
private struct DashCalls: Decodable { let items: [DashCall] }
private struct DashTask: Decodable {
    let id: DashTaskID? // BOREAL_DIALER_v823_WIDGET_ACTIONS
    let title: String?
    let type: String?
    let status: String?
    let due_at: String?
    let contact_name: String?
}
/// BOREAL_DIALER_v823_WIDGET_ACTIONS - a task id as a string whether the server sends a uuid or a number; an
/// unexpected shape must not empty the whole task list.
private struct DashTaskID: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else {
            value = nil
        }
    }
}
private struct DashTasksPayload: Decodable { let tasks: [DashTask] }
private struct DashTasks: Decodable { let data: DashTasksPayload }

extension DialerDashboardStore {
    static func missed(direction: String?, status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return (direction ?? "").lowercased() == "inbound" && ["no-answer", "missed", "busy", "failed"].contains(s)
    }

    static func refresh() async {
        var dashboard = load()
        var changed = false
        if let request = try? APIClient.shared.makeRequest(path: "/voice/recent-calls"),
           let data = try? await APIClient.shared.makeAuthorizedRequest(request),
           let calls = try? JSONDecoder().decode(DashCalls.self, from: data).items {
            dashboard.callsToday = calls.filter { call in
                guard let when = date(call.created_at) else { return false }
                return Calendar.current.isDateInToday(when)
            }.count
            dashboard.missed = calls.filter { missed(direction: $0.direction, status: $0.status) }.prefix(3).map { call in
                let number = call.phone_number.flatMap { DialerDeepLinkParser.normalizedPhone($0) }
                return DashboardItem(title: call.contact_name ?? call.phone_number ?? "Unknown", detail: time(date(call.created_at)), number: number)
            }
            changed = true
        }
        if let request = try? APIClient.shared.makeRequest(path: "/tasks?view=due_today"),
           let data = try? await APIClient.shared.makeAuthorizedRequest(request),
           let tasks = try? JSONDecoder().decode(DashTasks.self, from: data).data.tasks {
            dashboard.tasks = tasks.filter { ($0.status ?? "").lowercased() != "done" }.prefix(3).map { task in
                let who = task.contact_name.map { " · " + $0 } ?? ""
                return DashboardItem(title: task.title ?? "Task", detail: time(date(task.due_at)) + who, number: nil,
                                     taskId: task.id?.value) // BOREAL_DIALER_v823_WIDGET_ACTIONS
            }
            changed = true
        }
        if changed {
            dashboard.updatedAt = Date()
            save(dashboard)
        }
    }
}
