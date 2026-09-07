import SwiftUI
import WatchKit

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchEventStore
    var body: some View {
        NavigationStack {
            List {
                if let call = store.companionCall { CompanionCallView(call: call) }
                NavigationLink("Dial", destination: WatchDialView())
                NavigationLink("Call by Voice", destination: WatchVoiceCallView())
                NavigationLink("Contacts", destination: WatchContactsView())
                NavigationLink("Favorites", destination: WatchFavoritesView())
                NavigationLink("Recent Calls", destination: WatchRecentsView())
                NavigationLink("Log Outcome", destination: WatchDispositionView())
                NavigationLink("Notifications", destination: WatchNotificationsView())
                NavigationLink("Account", destination: WatchAccountView())
            }.navigationTitle("Boreal")
        }.onAppear { store.startCompanionOptimization() }
    }
}

struct WatchDialView: View {
    // BOREAL_DIALER_WATCH_KEYPAD_v1 - real phone keypad replaces the old TextField,
    // which was unusable on the wrist (Scribble/tiny keyboard). Same call plumbing.
    @State private var number: String
    @State private var line: BorealLine = .BF
    @State private var status: WatchCallStatus = .idle
    @State private var errorMessage: String?
    private let transport: any WatchCallTransport = ServerBridgeWatchCallTransport()
    private let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
    init(initialNumber: String = "") { _number = State(initialValue: initialNumber) }
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(number.isEmpty ? "Enter number" : number)
                    .font(.title3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(number.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                number.append(key)
                                WKInterfaceDevice.current().play(.click)
                            } label: {
                                Text(key).font(.title3).frame(maxWidth: .infinity, minHeight: 38)
                            }.buttonStyle(.bordered)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        if !number.isEmpty { number.removeLast(); WKInterfaceDevice.current().play(.click) }
                    } label: {
                        Image(systemName: "delete.left").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(number.isEmpty)
                    .onLongPressGesture { number = ""; WKInterfaceDevice.current().play(.click) }
                    Button { start() } label: {
                        Image(systemName: "phone.fill").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(number.isEmpty || status == .requesting)
                }
                Picker("Line", selection: $line) {
                    ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
                }.font(.caption2)
                if status != .idle { Text(statusText).font(.caption2).foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).font(.caption2).foregroundStyle(.red) }
            }.padding(.horizontal, 4)
        }.navigationTitle("Dial")
    }
    private var statusText: String {
        switch status {
        case .requesting: "Requesting callback…"
        case .waitingForCallback: "Waiting for carrier call…"
        case .bridging: "Bridging…"
        case .ringing: "Ringing…"
        case .connected: "Connected"
        case .ended: "Call ended"
        default: status.rawValue.capitalized
        }
    }
    private func start() {
        guard let destination = PhoneNumberNormalizer.normalize(number) else { errorMessage = "Enter a valid number"; return }
        let captured = CallRequest(destination: destination, line: line)
        status = .requesting; errorMessage = nil
        WKInterfaceDevice.current().play(.start)
        Task { do { status = try await transport.startCall(captured) }
            catch let error as WatchServiceError { status = .failed; errorMessage = error.safeMessage }
            catch { status = .failed; errorMessage = "Call request failed" }
        }
    }
}

struct WatchContactsView: View {
    @State private var query = ""; @State private var results: [ContactSummary] = []; @State private var message: String?
    @State private var line: BorealLine = .BF
    private let service: any WatchDirectoryService = DirectWatchDirectoryService()
    var body: some View {
        List {
            TextField("Search CRM", text: $query)
            Picker("Line", selection: $line) { ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) } }
            Button("Search") { search() }.disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
            if let message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            ForEach(results) { contact in
                NavigationLink(destination: ContactDetailView(contact: contact)) {
                    VStack(alignment: .leading) { Text(contact.name); if let company = contact.company { Text(company).font(.caption2) } }
                }
            }
        }.navigationTitle("Contacts")
    }
    private func search() { Task { do { results = try await service.search(query, line: line, limit: 10) }
        catch { message = "Search unavailable" } } }
}

struct ContactDetailView: View {
    let contact: ContactSummary
    var body: some View { List { Text(contact.name); if let company = contact.company { Text(company) }; Text(contact.primaryPhone); NavigationLink("Dial", destination: PrefilledDialView(number: contact.primaryPhone)) } }
}
struct PrefilledDialView: View { let number: String; var body: some View { WatchDialView(initialNumber: number) } }

struct WatchRecentsView: View {
    @State private var recents: [WatchRecentCall] = []; @State private var unavailable = false
    @State private var line: BorealLine = .BF
    private let service: any WatchRecentsService = DirectWatchRecentsService()
    var body: some View { List { Picker("Line", selection: $line) { ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) } }; if unavailable { Text("Recents unavailable").font(.caption) }; ForEach(recents) { recent in NavigationLink(destination: PrefilledDialView(number: recent.number)) { VStack(alignment: .leading) { Text(recent.name ?? recent.number); if recent.name != nil { Text(recent.number).font(.caption2).foregroundStyle(.secondary) } } } } }.navigationTitle("Recents").task(id: line) { do { unavailable = false; recents = try await service.fetch(line: line, limit: 25) } catch { unavailable = true } } }
}

// BOREAL_DIALER_WATCH_DISPOSITION_v1 - log a post-call outcome from the wrist:
// pick a recent call, choose an outcome, POST /watch/calls/:id/disposition.
struct WatchDispositionView: View {
    @State private var recents: [WatchRecentCall] = []
    @State private var line: BorealLine = .BF
    @State private var unavailable = false
    private let service: any WatchRecentsService = DirectWatchRecentsService()
    var body: some View {
        List {
            Picker("Line", selection: $line) {
                ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
            }.font(.caption2)
            if unavailable { Text("Unavailable").font(.caption2).foregroundStyle(.secondary) }
            ForEach(recents) { recent in
                NavigationLink(destination: DispositionPickerView(recent: recent)) {
                    VStack(alignment: .leading) {
                        Text(recent.name ?? recent.number)
                        Text(recent.number).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Log Outcome").task(id: line) {
            do { unavailable = false; recents = try await service.fetch(line: line, limit: 25) }
            catch { unavailable = true }
        }
    }
}

struct DispositionPickerView: View {
    let recent: WatchRecentCall
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var message: String?
    private let options: [(code: String, label: String)] = [
        ("connected", "Connected"), ("left_voicemail", "Left voicemail"), ("no_answer", "No answer"),
        ("follow_up", "Follow up"), ("demo_booked", "Demo booked"), ("documents_promised", "Docs promised"),
        ("needs_lender_review", "Needs lender review"), ("not_interested", "Not interested"), ("do_not_contact", "Do not contact"),
    ]
    var body: some View {
        List {
            Text(recent.name ?? recent.number).font(.headline)
            ForEach(options, id: \.code) { opt in
                Button(opt.label) { save(opt.code) }.disabled(saving)
            }
            if let message { Text(message).font(.caption2).foregroundStyle(.red) }
        }.navigationTitle("Outcome")
    }
    private func save(_ disposition: String) {
        saving = true; message = nil
        Task {
            do {
                let api = try WatchAPIClient()
                _ = try await api.request(path: "/watch/calls/\(recent.id)/disposition", method: "POST",
                    body: JSONEncoder().encode(["disposition": disposition]), line: recent.line)
                await MainActor.run { WKInterfaceDevice.current().play(.success); dismiss() }
            } catch let error as WatchServiceError {
                await MainActor.run { saving = false; message = error.safeMessage }
            } catch {
                await MainActor.run { saving = false; message = "Could not save" }
            }
        }
    }
}

struct WatchNotificationsView: View {
    @EnvironmentObject private var store: WatchEventStore
    var body: some View { List(store.events, id: \.callId) { event in VStack(alignment: .leading) { Text(event.subtitle); Text(event.title).font(.caption2).foregroundStyle(.secondary) } }.navigationTitle("Notifications") }
}

struct CompanionCallView: View {
    let call: WatchEvent
    @EnvironmentObject private var store: WatchEventStore
    var body: some View { Section("iPhone call") { Text(call.subtitle); HStack { Button { store.sendCompanionAction(.decline) } label: { Image(systemName: "phone.down.fill") }.tint(.red); Button { store.sendCompanionAction(.answer) } label: { Image(systemName: "phone.fill") }.tint(.green) }; Text("Controlled by nearby iPhone").font(.caption2).foregroundStyle(.secondary) } }
}

struct WatchAccountView: View {
    @EnvironmentObject private var store: WatchEventStore
    @State private var code = ""; @State private var linked = false; @State private var fallback = false
    @State private var message: String?
    var body: some View { List {
        if linked {
            Text("Linked")
            Toggle("Standalone cellular fallback", isOn: $fallback).onChange(of: fallback) { enabled in updateRouting(enabled) }
            Button("Sign Out", role: .destructive) { Task { do { try await WatchAuthService.shared.logout(client: WatchAPIClient()); await MainActor.run { store.clearSensitiveData(); linked = false; message = "Signed out on this Watch" } } catch { await MainActor.run { message = "Could not revoke this Watch. Try again." } } } }
        } else {
            Text("Link this Apple Watch").font(.headline)
            TextField("8-digit code", text: $code)
            Button("Link") { Task { do { try await WatchAuthService.shared.link(oneTimeCode: code); await MainActor.run { code = ""; linked = true; message = nil } } catch let error as WatchServiceError { await MainActor.run { message = error.safeMessage } } catch { await MainActor.run { message = "Unable to link Watch" } } } }.disabled(code.count != 8)
        }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }.navigationTitle("Account").task { linked = await WatchAuthService.shared.restore(); if linked { try? await WatchAPIClient().registerDevice() } } }
    private func updateRouting(_ enabled: Bool) { Task { do {
        guard let session = await WatchAuthService.shared.session else { return }
        struct Body: Encodable { let enabled: Bool }
        _ = try await WatchAPIClient().request(path: "/watch/devices/\(session.deviceId)/standalone-routing", method: "PUT", body: JSONEncoder().encode(Body(enabled: enabled)))
    } catch let error as WatchServiceError { await MainActor.run { fallback = false; message = error.safeMessage } } catch { await MainActor.run { fallback = false; message = "Unable to update fallback" } } } }
}


// BOREAL_DIALER_WATCH_VOICE_v1 - "Call <name>": dictate a name (TextFieldLink uses
// the watch dictation UI), search the CRM, then confirm the person before dialing.
struct WatchVoiceCallView: View {
    @State private var query = ""
    @State private var results: [ContactSummary] = []
    @State private var line: BorealLine = .BF
    @State private var message: String?
    @State private var searching = false
    private let service: any WatchDirectoryService = DirectWatchDirectoryService()
    var body: some View {
        List {
            TextFieldLink(prompt: Text("Say a name")) {
                Label("Speak a name", systemImage: "mic.fill")
            } onSubmit: { text in
                query = text
                search()
            }
            Picker("Line", selection: $line) {
                ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
            }.font(.caption2)
            if !query.isEmpty { Text("Heard: \(query)").font(.caption2).foregroundStyle(.secondary) }
            if searching { Text("Searching…").font(.caption2).foregroundStyle(.secondary) }
            if let message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            ForEach(results) { contact in
                NavigationLink(destination: ConfirmCallView(contact: contact, line: line)) {
                    VStack(alignment: .leading) {
                        Text(contact.name)
                        if let company = contact.company { Text(company).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("Voice Call")
    }
    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { message = "Say a full name"; return }
        searching = true; message = nil; results = []
        Task {
            do {
                let items = try await service.search(q, line: line, limit: 10)
                await MainActor.run { results = items; searching = false; if items.isEmpty { message = "No match for \(q)" } }
            } catch {
                await MainActor.run { searching = false; message = "Search unavailable" }
            }
        }
    }
}

struct ConfirmCallView: View {
    let contact: ContactSummary
    let line: BorealLine
    @State private var status: WatchCallStatus = .idle
    @State private var errorMessage: String?
    private let transport: any WatchCallTransport = ServerBridgeWatchCallTransport()
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.headline)
                if let company = contact.company { Text(company).font(.caption2).foregroundStyle(.secondary) }
                Text(contact.primaryPhone).font(.caption)
            }
            Button { start() } label: {
                Label("Call \(contact.name)", systemImage: "phone.fill")
            }.buttonStyle(.borderedProminent).tint(.green).disabled(status == .requesting)
            if status != .idle { Text(status.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.caption2).foregroundStyle(.red) }
        }.navigationTitle("Confirm")
    }
    private func start() {
        guard let destination = PhoneNumberNormalizer.normalize(contact.primaryPhone) else { errorMessage = "Invalid number"; return }
        status = .requesting; errorMessage = nil
        WKInterfaceDevice.current().play(.start)
        Task {
            do { status = try await transport.startCall(CallRequest(destination: destination, line: line, contactId: contact.id)) }
            catch let error as WatchServiceError { status = .failed; errorMessage = error.safeMessage }
            catch { status = .failed; errorMessage = "Call request failed" }
        }
    }
}


// BOREAL_DIALER_WATCH_FAVORITES_v1 - speed-dial derived from the CRM call history
// (most-called numbers), so no new server endpoint is needed. One tap to dial.
struct WatchFavoritesView: View {
    @State private var favorites: [WatchRecentCall] = []
    @State private var line: BorealLine = .BF
    @State private var unavailable = false
    private let service: any WatchRecentsService = DirectWatchRecentsService()
    var body: some View {
        List {
            Picker("Line", selection: $line) {
                ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
            }.font(.caption2)
            if unavailable { Text("Favorites unavailable").font(.caption2).foregroundStyle(.secondary) }
            if favorites.isEmpty && !unavailable {
                Text("Call people to build favorites").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(favorites) { fav in
                NavigationLink(destination: PrefilledDialView(number: fav.number)) {
                    VStack(alignment: .leading) {
                        Text(fav.name ?? fav.number)
                        if fav.name != nil { Text(fav.number).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("Favorites").task(id: line) { await load() }
    }
    private func load() async {
        do {
            let recents = try await service.fetch(line: line, limit: 25)
            var counts: [String: Int] = [:]
            var latest: [String: WatchRecentCall] = [:]
            for r in recents {
                counts[r.number, default: 0] += 1
                if let existing = latest[r.number] {
                    if r.occurredAt > existing.occurredAt { latest[r.number] = r }
                } else {
                    latest[r.number] = r
                }
            }
            let ranked = latest.values.sorted {
                (counts[$0.number] ?? 0, $0.occurredAt) > (counts[$1.number] ?? 0, $1.occurredAt)
            }
            await MainActor.run { favorites = Array(ranked.prefix(6)); unavailable = false }
        } catch {
            await MainActor.run { unavailable = true }
        }
    }
}
