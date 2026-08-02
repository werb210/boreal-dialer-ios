// BOREAL_DIALER_CALENDAR_TAB_v8
// Today's agenda plus tasks, matching the BF silo portal.
//
// Events come from GET /api/calendar/events, which proxies Microsoft Graph
// calendarView for the signed-in staff member. When O365 is not connected the
// server returns an empty list with status ok rather than an error, so an empty
// agenda is ambiguous - it is worth saying so rather than showing a bare "no
// events".
//
// Tasks come from GET /api/tasks (the unified `tasks` table), NOT from
// /api/calendar/tasks, which still reads the retired crm_tasks table.
import SwiftUI

struct CalendarEvent: Identifiable, Decodable {
    let id: String?
    let title: String?
    let start: String?
    let end: String?
    let location: String?
    let notes: String?
    let teamsLink: String?

    var identity: String { id ?? UUID().uuidString }
}

extension CalendarEvent {
    var startDate: Date? { CalendarFormatters.parse(start) }

    var timeLabel: String {
        guard let startDate else { return "" }
        let endDate = CalendarFormatters.parse(end)
        let from = CalendarFormatters.time.string(from: startDate)
        guard let endDate else { return from }
        return "\(from) – \(CalendarFormatters.time.string(from: endDate))"
    }
}

struct StaffTask: Identifiable, Decodable {
    let id: String
    let title: String?
    let body: String?
    let type: String?
    let status: String?
    let priority: String?
    let dueAt: String?
    let contactName: String?
    let queueName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body, type, status, priority
        case dueAt = "due_at"
        case contactName = "contact_name"
        case queueName = "queue_name"
    }

    var isComplete: Bool { (status ?? "").uppercased() == "COMPLETED" }

    var dueLabel: String? {
        guard let date = CalendarFormatters.parse(dueAt) else { return nil }
        return CalendarFormatters.time.string(from: date)
    }
}

enum CalendarFormatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    // Graph returns local ISO strings with no offset alongside fully qualified
    // ones, so try both rather than dropping half the events on the floor.
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: raw) { return d }

        let naive = DateFormatter()
        naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = naive.date(from: raw) { return d }

        naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        return naive.date(from: raw)
    }
}

private struct EventsEnvelope: Decodable { let data: [CalendarEvent] }
private struct TasksPayload: Decodable { let tasks: [StaffTask] }
private struct TasksEnvelope: Decodable { let data: TasksPayload }

@MainActor
final class CalendarViewModel: ObservableObject {
    enum TaskView: String, CaseIterable {
        case dueToday = "due_today"
        case overdue = "overdue"
        case upcoming = "upcoming"

        var label: String {
            switch self {
            case .dueToday: return "Today"
            case .overdue: return "Overdue"
            case .upcoming: return "Upcoming"
            }
        }
    }

    @Published var events: [CalendarEvent] = []
    @Published var tasks: [StaffTask] = []
    @Published var taskView: TaskView = .dueToday
    @Published var loading = false
    @Published var eventsUnavailable = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        async let eventsResult = loadEvents()
        async let tasksResult = loadTasks()
        _ = await (eventsResult, tasksResult)
        loading = false
    }

    private func loadEvents() async {
        // Today only - the agenda strip in the mockup is a single day.
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let iso = ISO8601DateFormatter()

        do {
            let path = "/calendar/events?start=\(iso.string(from: startOfDay))&end=\(iso.string(from: endOfDay))"
            let request = try APIClient.shared.makeRequest(path: path)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let decoded = try JSONDecoder().decode(EventsEnvelope.self, from: data).data
            events = decoded.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            // The server also returns an empty list when O365 is not connected,
            // so an empty agenda cannot be read as "nothing scheduled".
            eventsUnavailable = decoded.isEmpty
        } catch {
            events = []
            eventsUnavailable = true
        }
    }

    func loadTasks() async {
        do {
            let request = try APIClient.shared.makeRequest(path: "/tasks?view=\(taskView.rawValue)")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            tasks = try JSONDecoder().decode(TasksEnvelope.self, from: data).data.tasks
        } catch {
            tasks = []
            error = "Could not load tasks."
        }
    }

    func complete(_ task: StaffTask) async {
        do {
            let request = try APIClient.shared.makeRequest(
                path: "/tasks/\(task.id)/complete",
                method: "POST"
            )
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
            await loadTasks()
        } catch {
            self.error = "Couldn't complete that task."
        }
    }
}

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(CalendarFormatters.day.string(from: Date()))
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)

                agendaSection
                tasksSection
            }
            .padding(.bottom, 24)
        }
        .overlay {
            if viewModel.loading && viewModel.events.isEmpty && viewModel.tasks.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if viewModel.events.isEmpty {
                Text(viewModel.eventsUnavailable
                     ? "No events today, or Microsoft 365 isn't connected on this account."
                     : "No events today.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(viewModel.events, id: \.identity) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.timeLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 108, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title ?? "Untitled event")
                                .font(.body.weight(.medium))
                            if let location = event.location, !location.isEmpty {
                                Text(location).font(.caption).foregroundColor(.secondary)
                            }
                            if let link = event.teamsLink, !link.isEmpty, let url = URL(string: link) {
                                Link("Join Teams meeting", destination: url).font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Picker("View", selection: $viewModel.taskView) {
                ForEach(CalendarViewModel.TaskView.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: viewModel.taskView) { _ in
                Task { await viewModel.loadTasks() }
            }

            if viewModel.tasks.isEmpty {
                Text(viewModel.error ?? "Nothing here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(viewModel.tasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            Task { await viewModel.complete(task) }
                        } label: {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.isComplete ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(task.isComplete)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title ?? "Untitled task")
                                .font(.body)
                                .strikethrough(task.isComplete)
                            HStack(spacing: 6) {
                                if let type = task.type, !type.isEmpty {
                                    Text(type)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                if let contact = task.contactName, !contact.isEmpty {
                                    Text(contact).font(.caption).foregroundColor(.secondary)
                                }
                                if let due = task.dueLabel {
                                    Text(due).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if (task.priority ?? "") == "HIGH" {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
