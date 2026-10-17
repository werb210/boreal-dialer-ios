// BOREAL_DIALER_v821 - Account > Call hours: do-not-disturb by hours, saved to BF-Server (GET/PUT /staff/call-hours) so
// it applies wherever Boreal rings you (iPhone, Watch, cell bridge), not just to this phone's notifications.
import SwiftUI

@MainActor
final class CallHoursViewModel: ObservableObject {
    @Published var draft = CallHoursDraft.defaults(timezone: TimeZone.current.identifier)
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published var message: String?
    @Published var loadFailed = false
    private var saved: CallHoursDraft?

    var hasChanges: Bool { saved != draft }

    func load() async {
        loading = true
        message = nil
        do {
            let hours = try await CallHoursService.fetch()
            let loaded = CallHoursDraft(hours, deviceTimeZone: TimeZone.current.identifier)
            draft = loaded
            saved = loaded
            loadFailed = false
        } catch {
            loadFailed = true
            message = "Couldn't load your call hours. Pull to try again."
        }
        loading = false
    }

    func save() async {
        let errors = draft.validationErrors()
        guard errors.isEmpty else {
            message = errors.joined(separator: "\n")
            return
        }
        saving = true
        message = nil
        do {
            try await CallHoursService.save(draft.toCallHours())
            saved = draft
            message = "Saved."
        } catch {
            message = "Couldn't save. Check your connection and try again."
        }
        saving = false
    }
}

struct CallHoursView: View {
    @StateObject private var model = CallHoursViewModel()

    /// Canadian zones first, then the device's and whatever is saved, so the list stays short.
    private var zones: [String] {
        var list = ["America/Vancouver", "America/Edmonton", "America/Regina", "America/Winnipeg", "America/Toronto",
                    "America/Halifax", "America/St_Johns"]
        for extra in [TimeZone.current.identifier, model.draft.timezone] where !list.contains(extra) {
            list.insert(extra, at: 0)
        }
        return list
    }

    var body: some View {
        Form {
            Section {
                Toggle("Do not disturb outside call hours", isOn: $model.draft.enabled)
                Text("Outside your hours, Boreal calls go to voicemail instead of ringing you.")
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
            }

            Section("Time zone") {
                Picker("Time zone", selection: $model.draft.timezone) {
                    ForEach(zones, id: \.self) { zone in
                        Text(Self.zoneLabel(zone)).tag(zone)
                    }
                }
            }

            Section {
                if model.draft.customPerDay {
                    ForEach(CallHoursDay.allCases) { day in
                        dayRow(day)
                    }
                } else {
                    timeRow("Weekdays from", minutes: $model.draft.weekdayHours.start)
                    timeRow("Weekdays until", minutes: $model.draft.weekdayHours.end)
                    Toggle("Weekends, same hours", isOn: $model.draft.weekendOn)
                }
                Toggle("Set hours for each day", isOn: customBinding)
            } header: {
                Text("Hours you take calls")
            }

            Section {
                Toggle("Let urgent callers press 1 to ring through", isOn: $model.draft.urgentPassthrough)
                Text("Outside your hours, callers hear that you're unavailable and can press 1 if it's urgent.")
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
            }

            if let message = model.message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(message == "Saved." ? Theme.green : Theme.red)
                }
            }
        }
        .disabled(model.loading || model.saving)
        .navigationTitle("Call hours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.saving ? "Saving…" : "Save") {
                    Task { await model.save() }
                }
                .disabled(!model.hasChanges || model.saving || model.loadFailed)
            }
        }
        .overlay {
            if model.loading { ProgressView() }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    /// Switching to per-day starts every day from the simple layout's hours.
    private var customBinding: Binding<Bool> {
        Binding(
            get: { model.draft.customPerDay },
            set: { custom in
                if custom && !model.draft.customPerDay {
                    model.draft.days = model.draft.effectiveDays()
                }
                model.draft.customPerDay = custom
            }
        )
    }

    @ViewBuilder
    private func dayRow(_ day: CallHoursDay) -> some View {
        let binding = dayBinding(day)
        Toggle(day.label, isOn: binding.isOn)
        if binding.wrappedValue.isOn {
            timeRow("From", minutes: binding.start)
            timeRow("Until", minutes: binding.end)
        }
    }

    private func dayBinding(_ day: CallHoursDay) -> Binding<CallHoursDayRange> {
        Binding(
            get: { model.draft.days[day] ?? .off },
            set: { model.draft.days[day] = $0 }
        )
    }

    private func timeRow(_ title: String, minutes: Binding<Int>) -> some View {
        DatePicker(title, selection: Self.dateBinding(minutes), displayedComponents: .hourAndMinute)
    }

    /// Minutes after midnight <-> a time on a fixed day, for DatePicker.
    static func dateBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return Binding(
            get: { base.addingTimeInterval(TimeInterval(min(minutes.wrappedValue, 24 * 60 - 1) * 60)) },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    static func zoneLabel(_ identifier: String) -> String {
        let city = identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
        guard let zone = TimeZone(identifier: identifier),
              let abbreviation = zone.abbreviation() else { return city }
        return "\(city) (\(abbreviation))"
    }
}
