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

    // BOREAL_DIALER_CALENDAR_NAIVE_UTC_v181
    // The comment here used to claim Graph returns LOCAL strings with no
    // offset. It does not - the wall-clock is UTC, and Graph names the zone in
    // a sibling field the server was discarding. The unzoned string fell
    // through to the DateFormatter below, which has no timeZone set and so
    // defaults to the device's, and every event rendered six hours late in
    // Alberta. BF-portal hit the same thing and fixed it client-side in v711.
    //
    // v180 makes the server emit a true instant, so the ISO8601 branches now
    // handle every event. This fallback stays for older payloads and pins the
    // zone to UTC so it can never silently re-introduce the offset.
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: raw) { return d }

        let naive = DateFormatter()
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = TimeZone(identifier: "UTC")
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
    // BOREAL_DIALER_TABS_PRESENTATION_v26 - the day the strip has selected.
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var loading = false
    @Published var eventsUnavailable = false
    @Published var error: String?

    // BOREAL_DIALER_v803_UI - start-of-day dates in the visible week that have
    // at least one event, for the dots under the week strip.
    @Published var daysWithEvents: Set<Date> = []

    func load() async {
        loading = true
        error = nil
        async let eventsResult = loadEvents()
        async let tasksResult = loadTasks()
        async let weekResult = loadWeekDots()
        _ = await (eventsResult, tasksResult, weekResult)
        loading = false
    }

    // BOREAL_DIALER_v803_UI - the Monday-first week shown in the strip.
    nonisolated static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offsetToMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offsetToMonday, to: day) ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    // BOREAL_DIALER_v803_UI - one request for the whole week; dots are
    // decoration, so a failure leaves them off rather than showing an error.
    private func loadWeekDots() async {
        let calendar = Calendar.current
        let days = Self.weekDays(containing: Date(), calendar: calendar)
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        let iso = ISO8601DateFormatter()
        do {
            let path = "/calendar/events?start=\(iso.string(from: first))&end=\(iso.string(from: end))"
            let request = try APIClient.shared.makeRequest(path: path)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let week = try JSONDecoder().decode(EventsEnvelope.self, from: data).data
            daysWithEvents = Set(week.compactMap { $0.startDate.map { calendar.startOfDay(for: $0) } })
        } catch {
            daysWithEvents = []
        }
    }

    private func loadEvents() async {
        // Today only - the agenda strip in the mockup is a single day.
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
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
            publishNextMeetingToWatch()
        } catch {
            events = []
            eventsUnavailable = true
            // Do not clear the published meeting here. A failed refresh is not
            // evidence the meeting was cancelled, and O365 tokens expire often
            // enough that clearing on error would blank the face routinely.
        }
    }

    // BOREAL_DIALER_WATCH_NEXT_MEETING_v211
    private func publishNextMeetingToWatch() {
        // Only today's agenda is loaded, and only when the user is looking at
        // today - publishing while they browse next Tuesday would put next
        // Tuesday's meeting on the watch face.
        guard Calendar.current.isDateInToday(selectedDate) else { return }
        let now = Date()
        // events is already sorted ascending by startDate in loadEvents().
        let upcoming = events.first { ($0.startDate ?? .distantPast) > now }
        WatchSnapshotSync.publishNextMeeting(
            title: upcoming?.title,
            startsAt: upcoming?.startDate
        )
    }

    func loadTasks() async {
        do {
            let request = try APIClient.shared.makeRequest(path: "/tasks?view=\(taskView.rawValue)")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            tasks = try JSONDecoder().decode(TasksEnvelope.self, from: data).data.tasks
        } catch {
            // BOREAL_DIALER_CATCH_SHADOWING_v19 - self, not the catch binding.
            tasks = []
            self.error = "Could not load tasks."
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
    @Environment(\.openURL) private var openURL

    // BOREAL_DIALER_v803_UI - "October" over "Tuesday, the 14th", as in the mockup.
    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: viewModel.selectedDate)
    }

    private var daySubtitle: String {
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        let day = Calendar.current.component(.day, from: viewModel.selectedDate)
        let nth = ordinal.string(from: NSNumber(value: day)) ?? "\(day)"
        return "\(weekday.string(from: viewModel.selectedDate)), the \(nth)"
    }

    private var sectionDayLabel: String {
        if Calendar.current.isDateInToday(viewModel.selectedDate) { return "Schedule \u{00B7} Today" }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return "Schedule \u{00B7} " + f.string(from: viewModel.selectedDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // BOREAL_DIALER_v803_UI - mockup header. The app has no create-event
                // endpoint, so "+ Add" opens a new event in Outlook (Microsoft 365).
                ViewHeader(title: monthTitle, subtitle: daySubtitle) {
                    Menu {
                        Button {
                            if let url = URL(string: "https://outlook.office.com/calendar/deeplink/compose") {
                                openURL(url)
                            }
                        } label: {
                            Label("New event in Outlook", systemImage: "calendar.badge.plus")
                        }
                    } label: {
                        HeaderActionLabel(text: "+ Add")
                    }
                    .accessibilityLabel("Add")
                }

                weekStrip

                agendaSection
                tasksSection
            }
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .overlay {
            if viewModel.loading && viewModel.events.isEmpty && viewModel.tasks.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    // BOREAL_DIALER_TABS_PRESENTATION_v26 - the M-S strip from the mockup,
    // anchored on the current week.
    // BOREAL_DIALER_v803_UI - mockup week strip: 7 cells, 11pt day letter, 16pt
    // semibold date; today is a solid green 14pt-corner cell, the selected day is
    // outlined, and a 5pt green dot marks days that have events.
    private var weekStrip: some View {
        let calendar = Calendar.current
        let days = CalendarViewModel.weekDays(containing: Date(), calendar: calendar)

        let letters = DateFormatter()
        letters.dateFormat = "EEEEE"

        return HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                let selected = calendar.isDate(day, inSameDayAs: viewModel.selectedDate)
                let hasEvents = viewModel.daysWithEvents.contains(calendar.startOfDay(for: day))
                Button {
                    viewModel.selectedDate = day
                    Task { await viewModel.load() }
                } label: {
                    VStack(spacing: 4) {
                        Text(letters.string(from: day))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isToday ? Theme.onGreen : Theme.faint)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isToday ? Theme.onGreen : Theme.text)
                        Circle()
                            .fill(isToday ? Theme.onGreen : Theme.greenBright)
                            .frame(width: 5, height: 5)
                            .opacity(hasEvents ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isToday ? Theme.green : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selected && !isToday ? Theme.line2 : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var agendaSection: some View {
        // BOREAL_DIALER_v803_UI - "SCHEDULE . TODAY" and the mockup's event cards:
        // a 52pt right-aligned time column, then a surface2 card with a 3pt
        // coloured left edge (green for calls, sky for meetings).
        VStack(alignment: .leading, spacing: 0) {
            Text(sectionDayLabel.uppercased())
                .font(.system(size: 12, weight: .bold))
                .kerning(0.6)
                .foregroundColor(Theme.faint)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 5)

            if viewModel.events.isEmpty {
                // BOREAL_DIALER_v803_UI - friendly empty state; the Microsoft 365
                // hint stays because an unconnected account also returns no events.
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.faint)
                    Text("Nothing scheduled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(viewModel.eventsUnavailable
                         ? "No events on this day, or Microsoft 365 isn't connected on this account."
                         : "No events on this day.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            } else {
                ForEach(viewModel.events, id: \.identity) { event in
                    EventCardRow(event: event)
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // BOREAL_DIALER_v803_UI - "TASKS . n" section label.
            Text("Tasks \u{00B7} \(viewModel.tasks.count)".uppercased())
                .font(.system(size: 12, weight: .bold))
                .kerning(0.6)
                .foregroundColor(Theme.faint)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // BOREAL_DIALER_ROW_SEGMENT_STYLE_v31
            SegmentedBar(
                options: CalendarViewModel.TaskView.allCases,
                title: { $0.label },
                selection: $viewModel.taskView
            )
            .padding(.horizontal, 16)
            .onChange(of: viewModel.taskView) { _ in
                Task { await viewModel.loadTasks() }
            }

            if viewModel.tasks.isEmpty {
                Text(viewModel.error ?? "Nothing here.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            } else {
                ForEach(viewModel.tasks) { task in
                    // BOREAL_DIALER_v803_UI - mockup task row: 22pt rounded-square
                    // checkbox, 14.5pt title, 12pt faint detail, HIGH / MED tag.
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            Task { await viewModel.complete(task) }
                        } label: {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(task.isComplete ? Theme.green : Color.clear)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(task.isComplete ? Theme.green : Theme.line2, lineWidth: 2)
                                )
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundColor(Theme.onGreen)
                                        .opacity(task.isComplete ? 1 : 0)
                                )
                                .padding(.top, 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(task.isComplete)
                        .accessibilityLabel(task.isComplete ? "Completed" : "Mark complete")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title ?? "Untitled task")
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundColor(task.isComplete ? Theme.faint : Theme.text)
                                .strikethrough(task.isComplete)
                            Text(taskDetail(task))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.faint)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        // BOREAL_DIALER_TABS_PRESENTATION_v26 - HIGH / MED chips.
                        if let priority = task.priority?.uppercased(),
                           priority == "HIGH" || priority == "MED" || priority == "MEDIUM" {
                            PriorityTag(high: priority == "HIGH")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // BOREAL_DIALER_v803_UI - "Due 2:00 PM . Rivera Construction . Call".
    private func taskDetail(_ task: StaffTask) -> String {
        var parts: [String] = []
        if let due = task.dueLabel { parts.append("Due " + due) }
        if let contact = task.contactName, !contact.isEmpty { parts.append(contact) }
        if let type = task.type, !type.isEmpty { parts.append(type) }
        return parts.isEmpty ? "No due time" : parts.joined(separator: " \u{00B7} ")
    }
}

// BOREAL_DIALER_v803_UI - the mockup's .event row.
private struct EventCardRow: View {
    let event: CalendarEvent

    private var isCall: Bool {
        (event.title ?? "").lowercased().hasPrefix("call")
    }

    private var startLabel: String {
        guard let start = event.startDate else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: start)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let location = event.location, !location.isEmpty { parts.append(location) }
        if let start = event.startDate, let end = CalendarFormatters.parse(event.end) {
            let minutes = Int(end.timeIntervalSince(start) / 60)
            if minutes > 0 { parts.append("\(minutes) min") }
        }
        if parts.isEmpty { parts.append(event.timeLabel) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(startLabel)
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Theme.muted)
                .frame(width: 52, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Untitled event")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .lineLimit(2)
                if let link = event.teamsLink, !link.isEmpty, let url = URL(string: link) {
                    Link("Join Teams meeting", destination: url)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.greenBright)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface2)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isCall ? Theme.green : Theme.sky)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
    }
}
