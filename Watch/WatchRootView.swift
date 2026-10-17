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
                // BOREAL_DIALER_v804_WATCH - icons on every row; the three call
                // starters (Dial, Favorites, Calls Due) lead, the rest keep their order.
                NavigationLink(destination: WatchDialView()) { menuLabel("Dial", "circle.grid.3x3.fill") }
                NavigationLink(destination: WatchFavoritesView()) { menuLabel("Favorites", "star.fill") }
                // BOREAL_DIALER_WATCH_CALLBACKS_v219 - what you owe outranks
                // what already happened, so it sits above Recent Calls.
                NavigationLink(destination: WatchCallbacksView()) { menuLabel("Calls Due", "checklist") }
                NavigationLink(destination: WatchVoiceCallView()) { menuLabel("Call by Voice", "mic.fill") }
                NavigationLink(destination: WatchContactsView()) { menuLabel("Contacts", "person.crop.circle") }
                NavigationLink(destination: WatchRecentsView()) { menuLabel("Recent Calls", "clock") }
                NavigationLink(destination: WatchQuickTextRecipientsView()) { menuLabel("Quick Text", "message.fill") }
                NavigationLink(destination: WatchDispositionView()) { menuLabel("Log Outcome", "square.and.pencil") }
                NavigationLink(destination: WatchNotificationsView()) { menuLabel("Notifications", "bell.fill") }
                NavigationLink(destination: WatchAccountView()) { menuLabel("Account", "person.crop.circle.badge.checkmark") }
            }.navigationTitle("Boreal")
            // BOREAL_DIALER_WATCH_FACE_v371 - complication taps land on the screen they name.
            .navigationDestination(isPresented: complicationBinding("dial")) { WatchDialView() }
            .navigationDestination(isPresented: complicationBinding("recents")) { WatchRecentsView() }
            // BOREAL_DIALER_v820_WATCH - "Call back" on a missed-call / voicemail notification opens the keypad with
            // the number filled in; one tap places it (via iPhone when reachable).
            .navigationDestination(isPresented: Binding(get: { store.pendingDialNumber != nil },
                                                        set: { if !$0 { store.pendingDialNumber = nil } })) {
                WatchDialView(initialNumber: store.pendingDialNumber ?? "")
            }
            // BOREAL_DIALER_v821 - Quick reply / a tapped text or client message: quick replies + dictation.
            .navigationDestination(isPresented: Binding(get: { store.pendingReply != nil },
                                                        set: { if !$0 { store.pendingReply = nil } })) {
                if let target = store.pendingReply { WatchQuickReplyView(target: target) }
            }
            // BOREAL_DIALER_v821 - a tapped voicemail alert: the whole text and Call back.
            .navigationDestination(isPresented: Binding(get: { store.pendingVoicemail != nil },
                                                        set: { if !$0 { store.pendingVoicemail = nil } })) {
                if let alert = store.pendingVoicemail { WatchVoicemailAlertView(alert: alert) }
            }
        }.onAppear { store.startCompanionOptimization() }
    }
    // BOREAL_DIALER_v804_WATCH
    private func menuLabel(_ title: String, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(WatchTheme.greenBright)
        }
    }
}

// BOREAL_DIALER_v804_WATCH - the iPhone app's brand greens (UI/Components/Theme.swift
// is not compiled into the Watch target, so the two values are repeated here).
enum WatchTheme {
    static let green = Color(red: 47.0 / 255.0, green: 168.0 / 255.0, blue: 106.0 / 255.0)       // #2FA86A
    static let greenBright = Color(red: 84.0 / 255.0, green: 208.0 / 255.0, blue: 138.0 / 255.0) // #54D08A
    static let neutral = Color.gray.opacity(0.28)
}

// BOREAL_DIALER_v804_WATCH - initials circle + green phone glyph for call rows.
// The glyph is part of the row label, so a tap anywhere on the row (glyph
// included) takes the same path the row always took; no second tap target.
struct WatchCallRowLabel: View {
    let title: String
    let subtitle: String?
    var detail: String? = nil
    var detailColor: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(WatchTheme.green.opacity(0.35))
                Text(Self.initials(from: title)).font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                if let detail { Text(detail).font(.caption2).foregroundStyle(detailColor).lineLimit(1) }
            }
            Spacer(minLength: 2)
            Image(systemName: "phone.fill").foregroundStyle(WatchTheme.greenBright)
        }
    }

    static func initials(from name: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "#" : letters.joined()
    }
}

struct WatchDialView: View {
    // BOREAL_DIALER_WATCH_KEYPAD_v1 - real phone keypad replaces the old TextField,
    // which was unusable on the wrist (Scribble/tiny keyboard). Same call plumbing.
    @State private var number: String
    @State private var line: BorealLine = .BF
    @State private var errorMessage: String?
    // BOREAL_DIALER_v820_WATCH - iPhone VoIP when reachable, server callback bridge otherwise, with live status.
    @StateObject private var call = WatchCallController()
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
                // BOREAL_DIALER_v804_WATCH - phone-style display: large monospaced
                // digits, a dim "+1" hint while empty.
                Text(number.isEmpty ? "+1" : number)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(number.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
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
                            .background(RoundedRectangle(cornerRadius: keyHeight * 0.35).fill(WatchTheme.green)) // BOREAL_DIALER_v804_WATCH
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(number.isEmpty || call.isSettingUp)
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
                WatchCallStatusView(controller: call) // BOREAL_DIALER_v820_WATCH
                if let errorMessage { Text(errorMessage).font(.caption2).foregroundStyle(.red) }
            }.padding(.horizontal, 4)
        }.navigationTitle("Dial")
    }
    private func start() {
        guard let destination = PhoneNumberNormalizer.normalize(number) else { errorMessage = "Enter a valid number"; return }
        errorMessage = nil
        call.start(CallRequest(destination: destination, line: line)) // BOREAL_DIALER_v820_WATCH
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
    // BOREAL_DIALER_v804_WATCH - a prominent green Call (same prefilled dial
    // screen as before) and a Text row into the existing Quick Text flow.
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.headline)
                if let company = contact.company { Text(company).font(.caption2).foregroundStyle(.secondary) }
                Text(contact.primaryPhone).font(.caption).monospacedDigit()
            }
            NavigationLink(destination: PrefilledDialView(number: contact.primaryPhone)) {
                Label("Call", systemImage: "phone.fill").foregroundStyle(.white)
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(WatchTheme.green))
            NavigationLink(destination: WatchQuickTextTemplatesView(recipient: textRecipient, contactId: contact.id)) {
                Label("Text", systemImage: "message.fill")
            }
        }
        .navigationTitle("Contact")
    }
    // WatchQuickTextTemplatesView reads only name and number from its recipient.
    private var textRecipient: WatchRecentCall {
        WatchRecentCall(id: contact.id, name: contact.name, number: contact.primaryPhone,
                        direction: .outgoing, occurredAt: Date(), line: .BF)
    }
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
                    // BOREAL_DIALER_v804_WATCH
                    WatchCallRowLabel(title: recent.name ?? recent.number,
                                      subtitle: recent.name != nil ? recent.number : nil)
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
                    // BOREAL_DIALER_v804_WATCH
                    WatchCallRowLabel(title: callback.contactName ?? callback.number,
                                      subtitle: callback.title,
                                      detail: dueLabel(callback),
                                      detailColor: callback.overdue ? .orange : .secondary)
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

    // BOREAL_DIALER_v804_WATCH
    private func dueLabel(_ callback: WatchCallback) -> String? {
        if callback.overdue { return "Overdue" }
        guard let due = callback.dueAt else { return nil }
        return Self.clock.string(from: due)
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

// BOREAL_DIALER_v821 - Quick Text and a contact's Text now open the quick-reply screen: GET /templates/quick (snippets
// first, cached for a day; /watch/sms-templates as the fallback) plus dictation / Scribble. Sent via POST /watch/sms.
struct WatchQuickTextTemplatesView: View {
    let recipient: WatchRecentCall
    var contactId: String? = nil

    var body: some View {
        if let number = PhoneNumberNormalizer.normalize(recipient.number) {
            WatchQuickReplyView(target: .sms(phone: number, contactId: contactId, name: recipient.name))
        } else {
            Text("Invalid recipient number").font(.caption2).foregroundStyle(.red)
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
    // BOREAL_DIALER_v804_WATCH - two Buttons in one List row made a single
    // tappable cell on watchOS, so a tap could fire the wrong control or both.
    // Every control now sits in its own row with its own tap target.
    private let keypadRows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
    private var keyDiameter: CGFloat {
        max(30, min(46, (WKInterfaceDevice.current().screenBounds.width - 24) / 3 - 4))
    }
    var body: some View { Section("iPhone call") {
        Text(call.subtitle)
        // BOREAL_DIALER_v821 - the iPhone sends the caller's pipeline stage in `preview` for incoming calls.
        if call.kind == .incomingCall && !call.preview.isEmpty {
            Text(call.preview)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchTheme.greenBright)
        }
        Button { store.sendCompanionAction(.answer) } label: {
            Label("Answer", systemImage: "phone.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.green)
        Button { store.sendCompanionAction(.decline) } label: {
            Label("Decline", systemImage: "phone.down.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        Button {
            muted.toggle()
            store.sendInCallControl(muted ? .mute : .unmute)
        } label: {
            Label(muted ? "Unmute" : "Mute", systemImage: muted ? "mic.slash.fill" : "mic.fill")
                .foregroundStyle(muted ? Color.orange : Color.primary)
        }
        Button { showingKeypad = true } label: { Label("Keypad", systemImage: "circle.grid.3x3.fill") }
        Text("Controlled by nearby iPhone").font(.caption2).foregroundStyle(.secondary)
    }.sheet(isPresented: $showingKeypad) {
        // BOREAL_DIALER_v804_WATCH - 3x4 grid of round keys instead of a
        // 12-row list; each key sends the same DTMF control as before.
        ScrollView {
            VStack(spacing: 4) {
                ForEach(keypadRows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                store.sendInCallControl(.dtmf, digits: key)
                                WKInterfaceDevice.current().play(.click)
                            } label: {
                                Text(key)
                                    .font(.system(size: keyDiameter * 0.45, weight: .medium))
                                    .frame(width: keyDiameter, height: keyDiameter)
                                    .background(Circle().fill(WatchTheme.neutral))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }.navigationTitle("Keypad")
    } }
}

struct WatchAccountView: View {
    @EnvironmentObject private var store: WatchEventStore
    @State private var code = ""; @State private var linked = false; @State private var fallback = false
    @State private var message: String?
    var body: some View { List {
        if linked {
            linkStatusPill // BOREAL_DIALER_v804_WATCH
            // BOREAL_DIALER_v820_WATCH - say what the switch does. BF-Server only enables it when the staff member's cell
            // number is verified, which happens automatically when they sign in on the iPhone with a text code.
            Toggle("Answer calls on my Watch without iPhone", isOn: Binding(
                get: { fallback },
                set: { enabled in fallback = enabled; updateRouting(enabled) }
            ))
            Text("When your iPhone isn't reachable, Boreal calls ring your cell number, which rings this Watch. Press 1 to accept.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Your cell is the number you sign in to Boreal Dialer with on your iPhone; signing in with the text code verifies it.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Sign Out", role: .destructive) { Task { do { try await WatchAuthService.shared.logout(client: WatchAPIClient()); await MainActor.run { store.clearSensitiveData(); WatchStandaloneRouting.lastConfirmed = false; fallback = false; linked = false; message = "Signed out on this Watch" } } catch { await MainActor.run { message = "Could not revoke this Watch. Try again." } } } }
        } else {
            // BOREAL_DIALER_WATCH_LINK_COPY_v1
            // Auto-link already works: AccountSheet.swift:163 sends the code
            // over WCSession and WatchEventStore.handle() links silently. This
            // screen previously led with a bare code field, which made the
            // supported path look unavailable. Say where the code comes from;
            // keep manual entry collapsed for an out-of-range phone.
            // BOREAL_DIALER_v804_WATCH - one sentence plus a status pill.
            linkStatusPill
            Text("On iPhone tap Settings > Account > Link Apple Watch.")
                .font(.caption2).foregroundStyle(.secondary)
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
    }.navigationTitle("Account").task {
        linked = await WatchAuthService.shared.restore()
        // BOREAL_DIALER_v820_WATCH - BF-Server has no read for this switch, so show the last state it confirmed.
        fallback = linked && WatchStandaloneRouting.lastConfirmed
        if linked { try? await WatchAPIClient().registerDevice() }
    } }
    // BOREAL_DIALER_v804_WATCH
    private var linkStatusPill: some View {
        HStack(spacing: 4) {
            Circle().fill(linked ? WatchTheme.greenBright : Color.gray).frame(width: 6, height: 6)
            Text(linked ? "Linked" : "Not linked").font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill((linked ? WatchTheme.green : Color.gray).opacity(0.3)))
    }
    private func updateRouting(_ enabled: Bool) { Task { do {
        guard let session = await WatchAuthService.shared.session else { return }
        struct Body: Encodable { let enabled: Bool }
        _ = try await WatchAPIClient().request(path: "/watch/devices/\(session.deviceId)/standalone-routing", method: "PUT", body: JSONEncoder().encode(Body(enabled: enabled)))
        // BOREAL_DIALER_v820_WATCH - remember what the server accepted and confirm it on the wrist.
        await MainActor.run {
            WatchStandaloneRouting.lastConfirmed = enabled
            message = enabled ? "On. Boreal calls will ring this Watch when your iPhone isn't reachable." : "Off"
        }
    } catch let error as WatchServiceError { await MainActor.run { fallback = false; WatchStandaloneRouting.lastConfirmed = false; message = error.safeMessage } } catch { await MainActor.run { fallback = false; message = "Unable to update fallback" } } } }
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
    @State private var errorMessage: String?
    @StateObject private var call = WatchCallController() // BOREAL_DIALER_v820_WATCH
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.headline)
                if let company = contact.company { Text(company).font(.caption2).foregroundStyle(.secondary) }
                Text(contact.primaryPhone).font(.caption)
            }
            Button { start() } label: {
                Label("Call \(contact.name)", systemImage: "phone.fill")
            }.buttonStyle(.borderedProminent).tint(WatchTheme.green).disabled(call.isSettingUp) // BOREAL_DIALER_v804_WATCH
            WatchCallStatusView(controller: call) // BOREAL_DIALER_v820_WATCH
            if let errorMessage { Text(errorMessage).font(.caption2).foregroundStyle(.red) }
        }.navigationTitle("Confirm")
    }
    private func start() {
        guard let destination = PhoneNumberNormalizer.normalize(contact.primaryPhone) else { errorMessage = "Invalid number"; return }
        errorMessage = nil
        call.start(CallRequest(destination: destination, line: line, contactId: contact.id)) // BOREAL_DIALER_v820_WATCH
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
                    // BOREAL_DIALER_v804_WATCH
                    WatchCallRowLabel(title: fav.name ?? fav.number,
                                      subtitle: fav.name != nil ? fav.number : nil)
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

// BOREAL_DIALER_v820_WATCH - last standalone-routing state BF-Server accepted (PUT /watch/devices/:id/standalone-routing
// is write-only). Cleared with the Watch session on sign-out.
enum WatchStandaloneRouting {
    private static let key = "boreal.watch.standaloneRouting.confirmed"
    static var lastConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
