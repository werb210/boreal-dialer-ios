import SwiftUI
import WatchKit

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchEventStore
    private func complicationBinding(_ target: String) -> Binding<Bool> {
        Binding(get: { store.complicationTarget == target },
                set: { if !$0 { store.complicationTarget = nil } })
    }
    var body: some View {
        NavigationStack {
            List {
                if let call = store.companionCall { CompanionCallView(call: call) }
                // BOREAL_DIALER_WATCH_ENROLL_DELIVERY_v173 - an unpaired wrist
                // used to look identical to a paired one: the menu rendered
                // either way and only the server-backed screens failed, which
                // reads as "it's paired but broken". Say it plainly instead.
                if let pairingError = store.lastLinkError {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not paired").font(.caption).foregroundStyle(.orange)
                        Text(pairingError).font(.caption2).foregroundStyle(.secondary)
                        Text("Open Boreal on your iPhone").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                NavigationLink("Dial", destination: WatchDialView())
                NavigationLink("Call by Voice", destination: WatchVoiceCallView())
                NavigationLink("Contacts", destination: WatchContactsView())
                NavigationLink("Favorites", destination: WatchFavoritesView())
                // BOREAL_DIALER_WATCH_CALLBACKS_v219 - what you owe outranks
                // what already happened, so it sits above Recent Calls.
                NavigationLink("Calls Due", destination: WatchCallbacksView())
                NavigationLink("Recent Calls", destination: WatchRecentsView())
                NavigationLink("Quick Text", destination: WatchQuickTextRecipientsView())
                NavigationLink("Log Outcome", destination: WatchDispositionView())
                NavigationLink("Notifications", destination: WatchNotificationsView())
                NavigationLink("Account", destination: WatchAccountView())
            }.navigationTitle("Boreal")
            // BOREAL_DIALER_WATCH_FACE_v371 - complication taps land on the screen they name.
            .navigationDestination(isPresented: complicationBinding("dial")) { WatchDialView() }
            .navigationDestination(isPresented: complicationBinding("recents")) { WatchRecentsView() }
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
    /// BOREAL_DIALER_WATCH_DIALPAD_FIT_v314 - six rows (display, 4 key rows, actions)
    /// inside the usable height, clamped so small and large watches stay tappable.
    static func keyHeight(forScreenHeight height: CGFloat) -> CGFloat {
        max(22, min(34, (height - 78) / 6))
    }
    private var keyHeight: CGFloat { Self.keyHeight(forScreenHeight: WKInterfaceDevice.current().screenBounds.height) }
    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                Text(number.isEmpty ? "Enter number" : number)
                    .font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(number.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
                // BOREAL_DIALER_WATCH_DIALPAD_FIT_v314 - compact plain keys sized from the
                // screen: display + four key rows + action row fit without scrolling.
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                number.append(key)
                                WKInterfaceDevice.current().play(.click)
                            } label: {
                                Text(key)
                                    .font(.system(size: keyHeight * 0.55, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: keyHeight)
                                    .background(RoundedRectangle(cornerRadius: keyHeight * 0.35).fill(Color.gray.opacity(0.28)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 3) {
                    Button {
                        if !number.isEmpty { number.removeLast(); WKInterfaceDevice.current().play(.click) }
                    } label: {
                        Image(systemName: "delete.left")
                            .frame(maxWidth: .infinity)
                            .frame(height: keyHeight)
                            .background(RoundedRectangle(cornerRadius: keyHeight * 0.35).fill(Color.gray.opacity(0.28)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(number.isEmpty)
                    .onLongPressGesture { number = ""; WKInterfaceDevice.current().play(.click) }
                    Button { start() } label: {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: keyHeight)
                            .background(RoundedRectangle(cornerRadius: keyHeight * 0.35).fill(Color.green))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(number.isEmpty || status == .requesting)
                }
                // BOREAL_DIALER_WATCH_DIAL_FIT_v173 - the default inline style
                // renders a fixed-height wheel inside this VStack and clipped its
                // own value ("BF" cut by the frame). The navigationLink style is
                // what Favorites and Recents already use, where it reads cleanly
                // as a row, and it costs one line of height instead of three.
                // BOREAL_DIALER_SINGLE_LINE_v174 - BorealLine.enabled is [.BF]; a picker
                // with one option is pure noise on a 41mm screen.
                if BorealLine.enabled.count > 1 {
                    Picker("Line", selection: $line) {
                        ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    .font(.caption2)
                }
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
    @State private var searching = false // BOREAL_DIALER_WATCH_CONTACT_SEARCH_v331
    private let service: any WatchDirectoryService = DirectWatchDirectoryService()
    var body: some View {
        List {
            TextField("Search CRM", text: $query)
            // BOREAL_DIALER_SINGLE_LINE_v174 - BorealLine.enabled is [.BF]; a picker
            // with one option is pure noise on a 41mm screen.
            if BorealLine.enabled.count > 1 {
                Picker("Line", selection: $line) { ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            Button("Search") { search() }.disabled(searching || query.trimmingCharacters(in: .whitespaces).count < 2)
            if searching { Text("Searching…").font(.caption2).foregroundStyle(.secondary) }
            if let message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            ForEach(results) { contact in
                NavigationLink(destination: ContactDetailView(contact: contact)) {
                    VStack(alignment: .leading) { Text(contact.name); if let company = contact.company { Text(company).font(.caption2) } }
                }
            }
        }.navigationTitle("Contacts")
    }
    // BOREAL_DIALER_WATCH_CONTACT_SEARCH_v331
    // Two faults, which together made the screen look like it was echoing back
    // whatever was typed. The results were assigned from a Task that is not
    // MainActor-isolated, so the @State write happened off the main actor and
    // the list was never redrawn - WatchVoiceCallView's search already hops to
    // the main actor for exactly this reason. And there was no empty or busy
    // state, so a search that returned nothing left the screen showing only the
    // text field, still holding the query.
    @MainActor
    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        searching = true
        message = nil
        results = []
        Task {
            do {
                let items = try await service.search(q, line: line, limit: 10)
                await MainActor.run {
                    results = items
                    searching = false
                    if items.isEmpty { message = "No match for \(q)" }
                }
            } catch {
                await MainActor.run {
                    searching = false
                    message = "Search unavailable"
                }
            }
        }
    }
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
    var body: some View {
        List {
            // BOREAL_DIALER_SINGLE_LINE_v174 - BorealLine.enabled is [.BF]; a picker
            // with one option is pure noise on a 41mm screen.
            if BorealLine.enabled.count > 1 {
                Picker("Line", selection: $line) { ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            if unavailable { Text("Recents unavailable").font(.caption) }
            ForEach(recents) { recent in
                NavigationLink(destination: PrefilledDialView(number: recent.number)) {
                    VStack(alignment: .leading) {
                        Text(recent.name ?? recent.number)
                        if recent.name != nil { Text(recent.number).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Recents")
        .task(id: line) {
            do { unavailable = false; recents = try await service.fetch(line: line, limit: 25) }
            catch { unavailable = true }
        }
    }
}

// BOREAL_DIALER_WATCH_CALLBACKS_v219
struct WatchCallbacksView: View {
    @State private var callbacks: [WatchCallback] = []
    @State private var unavailable = false
    @State private var loaded = false
    @State private var line: BorealLine = .BF
    private let service: any WatchCallbacksService = DirectWatchCallbacksService()

    var body: some View {
        List {
            if BorealLine.enabled.count > 1 {
                Picker("Line", selection: $line) { ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            if unavailable {
                Text("Calls due unavailable").font(.caption)
            } else if loaded && callbacks.isEmpty {
                // An empty list and a failed fetch must not look the same.
                Text("Nothing due").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(callbacks) { callback in
                // Opens the dial screen rather than dialling on tap. A misplaced
                // tap on a wrist should not ring a client.
                NavigationLink(destination: PrefilledDialView(number: callback.number)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(callback.contactName ?? callback.number)
                        Text(callback.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if callback.overdue {
                            Text("Overdue").font(.caption2).foregroundStyle(.orange)
                        } else if let due = callback.dueAt {
                            Text(Self.clock.string(from: due)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Calls Due")
        .task(id: line) {
            do {
                unavailable = false
                callbacks = try await service.fetch(line: line, limit: 20)
            } catch {
                unavailable = true
            }
            loaded = true
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}

struct WatchQuickTextRecipientsView: View {
    @State private var recents: [WatchRecentCall] = []
    @State private var line: BorealLine = .BF
    @State private var unavailable = false
    private let service: any WatchRecentsService = DirectWatchRecentsService()

    var body: some View {
        List {
            // BOREAL_DIALER_SINGLE_LINE_v174 - BorealLine.enabled is [.BF]; a picker
            // with one option is pure noise on a 41mm screen.
            if BorealLine.enabled.count > 1 {
                Picker("Line", selection: $line) {
                ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
            }
                .font(.caption2)
            }
            if unavailable {
                Text("Recents unavailable").font(.caption2).foregroundStyle(.secondary)
            } else if recents.isEmpty {
                Text("No recent recipients").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(recents) { recent in
                NavigationLink(destination: WatchQuickTextTemplatesView(recipient: recent)) {
                    VStack(alignment: .leading) {
                        Text(recent.name ?? recent.number)
                        if recent.name != nil {
                            Text(recent.number).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Quick Text")
        .task(id: line) {
            do {
                recents = try await service.fetch(line: line, limit: 25)
                unavailable = false
            } catch {
                recents = []
                unavailable = true
            }
        }
    }
}

struct WatchQuickTextTemplatesView: View {
    let recipient: WatchRecentCall
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [WatchSMSTemplate] = []
    @State private var loading = true
    @State private var sendingTemplateID: String?
    @State private var errorMessage: String?
    private let service: any WatchSMSService = DirectWatchSMSService()

    var body: some View {
        List {
            Text(recipient.name ?? recipient.number).font(.headline)
            if loading { ProgressView() }
            ForEach(templates) { template in
                Button {
                    send(template)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name)
                        Text(template.body).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .disabled(sendingTemplateID != nil)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption2).foregroundStyle(.red)
            }
        }
        .navigationTitle("Choose Text")
        .task { await loadTemplates() }
    }

    private func loadTemplates() async {
        do {
            templates = try await service.fetchTemplates()
            errorMessage = templates.isEmpty ? "No quick texts available" : nil
        } catch let error as WatchServiceError {
            errorMessage = error.safeMessage
        } catch {
            errorMessage = "Quick texts unavailable"
        }
        loading = false
    }

    private func send(_ template: WatchSMSTemplate) {
        guard let number = PhoneNumberNormalizer.normalize(recipient.number) else {
            errorMessage = "Invalid recipient number"
            return
        }
        sendingTemplateID = template.id
        errorMessage = nil
        Task {
            do {
                try await service.send(to: number, body: template.body)
                await MainActor.run {
                    WKInterfaceDevice.current().play(.success)
                    dismiss()
                }
            } catch let error as WatchServiceError {
                await MainActor.run { sendingTemplateID = nil; errorMessage = error.safeMessage }
            } catch {
                await MainActor.run { sendingTemplateID = nil; errorMessage = "Could not send text" }
            }
        }
    }
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
            // BOREAL_DIALER_SINGLE_LINE_v174 - BorealLine.enabled is [.BF]; a picker
            // with one option is pure noise on a 41mm screen.
            if BorealLine.enabled.count > 1 {
                Picker("Line", selection: $line) {
                ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
            }
                .font(.caption2)
            }
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

// BOREAL_DIALER_WATCH_NOTIFICATIONS_v331 - the screen was a bare List over
// store.events keyed on callId, so with nothing delivered it rendered an empty
// list with no text of any kind, and with several non-call events delivered the
// colliding ids collapsed them. Say what the screen is for when it is empty, and
// give every event its own row and its own time.
struct WatchNotificationsView: View {
    @EnvironmentObject private var store: WatchEventStore
    var body: some View {
        List {
            if store.events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing yet")
                    Text("Calls, messages, tasks and meetings show up here once your iPhone sends one.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(store.events, id: \.rowId) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.subtitle)
                        Text(event.title).font(.caption2).foregroundStyle(.secondary)
                        Text(event.occurredAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Notifications")
    }
}

struct CompanionCallView: View {
    let call: WatchEvent
    @EnvironmentObject private var store: WatchEventStore
    // BOREAL_DIALER_WATCH_INCALL_v1 - mute and keypad during an active call.
    @State private var muted = false
    @State private var showingKeypad = false
    var body: some View { Section("iPhone call") {
        Text(call.subtitle)
        HStack {
            Button { store.sendCompanionAction(.decline) } label: { Image(systemName: "phone.down.fill") }.tint(.red)
            Button { store.sendCompanionAction(.answer) } label: { Image(systemName: "phone.fill") }.tint(.green)
        }
        HStack {
            Button {
                muted.toggle()
                store.sendInCallControl(muted ? .mute : .unmute)
            } label: {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
            }.tint(muted ? .orange : .gray)
            Button { showingKeypad = true } label: { Image(systemName: "circle.grid.3x3.fill") }.tint(.gray)
        }
        Text("Controlled by nearby iPhone").font(.caption2).foregroundStyle(.secondary)
    }.sheet(isPresented: $showingKeypad) {
        List {
            ForEach(["1","2","3","4","5","6","7","8","9","*","0","#"], id: \.self) { key in
                Button(key) { store.sendInCallControl(.dtmf, digits: key) }
            }
        }.navigationTitle("Keypad")
    } }
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
            // BOREAL_DIALER_WATCH_LINK_COPY_v1
            // Auto-link already works: AccountSheet.swift:163 sends the code
            // over WCSession and WatchEventStore.handle() links silently. This
            // screen previously led with a bare code field, which made the
            // supported path look unavailable. Say where the code comes from;
            // keep manual entry collapsed for an out-of-range phone.
            Text("Link this Apple Watch").font(.headline)
            Text("On your iPhone, open Boreal Dialer → Settings → Account → Link Apple Watch. This Watch links itself.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Waiting for iPhone…").font(.caption2).foregroundStyle(.tertiary)
            // BOREAL_DIALER_WATCH_LINK_COPY_v2 - v1 used DisclosureGroup, which
            // SwiftUI marks unavailable on watchOS; the target would not
            // compile. A NavigationLink to a small screen is the watchOS
            // pattern for a rarely-needed secondary path, and reads better on
            // a 40mm display than an inline expanding field.
            NavigationLink("Enter code manually") {
                WatchManualLinkView(linked: $linked, message: $message)
            }.font(.caption2)
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
            // BOREAL_DIALER_SINGLE_LINE_v174 - BorealLine.enabled is [.BF]; a picker
            // with one option is pure noise on a 41mm screen.
            if BorealLine.enabled.count > 1 {
                Picker("Line", selection: $line) {
                ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
            }
                .font(.caption2)
            }
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
            // BOREAL_DIALER_SINGLE_LINE_v174 - BorealLine.enabled is [.BF]; a picker
            // with one option is pure noise on a 41mm screen.
            if BorealLine.enabled.count > 1 {
                Picker("Line", selection: $line) {
                ForEach(BorealLine.enabled, id: \.self) { Text($0.rawValue).tag($0) }
            }
                .font(.caption2)
            }
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


// BOREAL_DIALER_WATCH_LINK_COPY_v2
// Fallback only: the phone normally pushes the code over WCSession and
// WatchEventStore links silently. This exists for a phone that is off or out
// of range.
struct WatchManualLinkView: View {
    @Binding var linked: Bool
    @Binding var message: String?
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        List {
            TextField("8-digit code", text: $code)
            Button("Link") {
                Task {
                    do {
                        try await WatchAuthService.shared.link(oneTimeCode: code)
                        await MainActor.run { code = ""; linked = true; message = nil; dismiss() }
                    } catch let error as WatchServiceError {
                        await MainActor.run { message = error.safeMessage }
                    } catch {
                        await MainActor.run { message = "Unable to link Watch" }
                    }
                }
            }.disabled(code.count != 8)
            if let message { Text(message).font(.caption2).foregroundStyle(.secondary) }
        }
        .navigationTitle("Manual link")
    }
}
