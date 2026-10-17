// BOREAL_DIALER_CALLS_TAB_v11
// The Calls tab: Keypad, Recents, Voicemail - the three sub-tabs from the
// concept mockup. Keypad is the existing DialerView.
//
//   GET /api/voice/recent-calls    -> { ok, items: [...] }
//   GET /api/crm/voicemails        -> { success, data: [...] }
//   GET /api/crm/voicemails/:id/audio (staff JWT) -> mp3 bytes
//
// Recents and Voicemail are both server-backed. The old CallHistoryView read
// local CoreData, so it only showed calls placed from this handset.
import SwiftUI
import AVFoundation

// BOREAL_DIALER_CALLS_TAP_THROUGH_v35
// Recents and Voicemail carry only the contact's id, name and number. That is
// enough to open the record - ContactDetailView loads the timeline by id and
// the header degrades to what it was given.
private func stubContact(id: String, name: String?, phone: String?) -> CRMContact {
    CRMContact(
        id: id,
        name: name,
        firstName: nil,
        lastName: nil,
        email: nil,
        phone: phone,
        companyName: nil,
        leadStatus: nil
    )
}

struct CallsView: View {
    // BOREAL_DIALER_UIKIT_AND_SECTION_v13 - not `Section`: that shadows
    // SwiftUI.Section throughout this type.
    enum CallSection: String, CaseIterable {
        case keypad = "Keypad"
        case recents = "Recents"
        case voicemail = "Voicemail"
    }

    @State private var section: CallSection = .keypad
    // BOREAL_DIALER_v821 - the voicemail a tapped VOICEMAIL alert names; VoicemailView opens it once loaded.
    @State private var focusVoicemailId: String?
    @ObservedObject private var deepLinks = DeepLinkCoordinator.shared
    // BOREAL_DIALER_v803_UI - account / settings moved here from the tab rail.
    @State private var showAccount = false

    var body: some View {
        VStack(spacing: 0) {
            // BOREAL_DIALER_ROW_SEGMENT_STYLE_v31
            // BOREAL_DIALER_v803_UI - the account button sits at the end of this row.
            HStack(spacing: 10) {
                SegmentedBar(
                    options: CallSection.allCases,
                    title: { $0.rawValue },
                    selection: $section
                )
                Button {
                    showAccount = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.muted)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Account and settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Rectangle().fill(Theme.line).frame(height: 1)

            switch section {
            case .keypad:
                // BOREAL_DIALER_MOCKUP_LAYOUT_v60 - mockup order: number, Quick Call, keypad.
                DialerView()
            case .recents: RecentCallsView()
            case .voicemail: VoicemailView(focusId: $focusVoicemailId) // BOREAL_DIALER_v821
            }
        }
        .onChange(of: deepLinks.pending) { link in
            if link != nil { section = .keypad }
        }
        // BOREAL_DIALER_v820_WATCH - missed-call alert -> Recents, voicemail alert -> Voicemail.
        // BOREAL_DIALER_v821 - a voicemail alert that names its voicemail opens that one.
        .onReceive(AlertNavigator.shared.$pending) { destination in
            guard let destination else { return }
            switch destination {
            case .calls:
                section = CallSection.recents
            case .voicemail:
                section = CallSection.voicemail
            case .voicemailMessage(let id):
                focusVoicemailId = id
                section = CallSection.voicemail
            default:
                return
            }
            AlertNavigator.shared.finish(destination)
        }
        .sheet(isPresented: $showAccount) { AccountSheet() } // BOREAL_DIALER_v803_UI
    }
}

// MARK: - Recents

struct RecentCall: Identifiable, Decodable {
    let id: String
    let direction: String?
    let status: String?
    let durationSeconds: Int?
    let createdAt: String?
    let phoneNumber: String?
    let contactId: String?
    let contactName: String?
    // BOREAL_DIALER_v821 - for the row's "Call summary". Read when /voice/recent-calls includes it.
    let callSid: String?
    let twilioCallSid: String?

    enum CodingKeys: String, CodingKey {
        case id, direction, status
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case phoneNumber = "phone_number"
        case contactId = "contact_id"
        case contactName = "contact_name"
        case callSid = "call_sid"
        case twilioCallSid = "twilio_call_sid"
    }

    /// BOREAL_DIALER_v821 - the reference GET /calls/{callSid}/summary is asked with: the Twilio CallSid when the row
    /// has one, otherwise the row's own id (BF-Server resolves either, as it does for dispositions).
    var summaryRef: String? {
        let candidates = [callSid, twilioCallSid, id]
        return candidates.compactMap { $0 }.first { AfterCallSummaryService.pathSegment($0) != nil }
    }

    var isInbound: Bool { (direction ?? "").lowercased() == "inbound" }
    var missed: Bool {
        let s = (status ?? "").lowercased()
        return isInbound && (s == "no-answer" || s == "missed" || s == "busy" || s == "failed")
    }

    var title: String { contactName ?? PhoneFormat.display(phoneNumber).ifEmpty("Unknown") }

    var subtitle: String {
        // BOREAL_DIALER_CALLS_PRESENTATION_v23 - "Outgoing · 4m 12s · 9:02 AM".
        var parts: [String] = [missed ? "Missed" : (isInbound ? "Incoming" : "Outgoing")]
        if let seconds = durationSeconds, seconds > 0 {
            parts.append(seconds >= 60
                         ? "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
                         : "\(seconds)s")
        }
        if let date = CalendarFormatters.parse(createdAt) {
            parts.append(CalendarFormatters.time.string(from: date))
        }
        return parts.joined(separator: " · ")
    }
}

private struct RecentCallsEnvelope: Decodable { let items: [RecentCall] }

@MainActor
final class RecentCallsViewModel: ObservableObject {
    @Published var calls: [RecentCall] = []
    @Published var loading = false
    @Published var error: String?

    // Preserves server order (created_at DESC) inside each day.
    var grouped: [(String, [RecentCall])] {
        var order: [String] = []
        var buckets: [String: [RecentCall]] = [:]
        for call in calls {
            let key = DayBucket.label(for: call.createdAt)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(call)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    func load() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/voice/recent-calls")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            calls = try JSONDecoder().decode(RecentCallsEnvelope.self, from: data).items
            WidgetSnapshotStore.save(calls.compactMap { call in
                guard let number = call.phoneNumber,
                      let normalized = DialerDeepLinkParser.normalizedPhone(number) else { return nil }
                return WidgetContact(name: call.title, number: normalized)
            })
        } catch {
            self.error = "Could not load recent calls."
        }
        loading = false
    }
}

struct RecentCallsView: View {
    @StateObject private var viewModel = RecentCallsViewModel()
    @State private var summaryFor: RecentCall? // BOREAL_DIALER_v821

    var body: some View {
        // BOREAL_DIALER_CALLS_TAP_THROUGH_v35
        NavigationStack {
        VStack(spacing: 0) {
        AfterCallSummaryBanner() // BOREAL_DIALER_v821 - the call that just ended
        Group {
            if viewModel.loading && viewModel.calls.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.calls.isEmpty {
                Text(viewModel.error ?? "No recent calls")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // BOREAL_DIALER_CALLS_PRESENTATION_v23 - grouped by day, with
                // avatars, matching the concept mockup.
                List {
                    ForEach(viewModel.grouped, id: \.0) { day, calls in
                        Section {
                            ForEach(calls) { call in
                                rowContent(for: call)
                            }
                        } header: {
                            SectionLabel(text: day)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .refreshable { await viewModel.load() }
            }
        }
        }
        .toolbar(.hidden, for: .navigationBar) // BOREAL_DIALER_v803_UI - no empty bar above the list
        }
        .task { await viewModel.load() }
        // BOREAL_DIALER_v821 - "Call summary" from a row's menu.
        .sheet(item: $summaryFor) { call in
            AfterCallSummarySheet(callSid: call.summaryRef ?? call.id, title: call.title)
        }
    }

    // A row is navigable only when the call matched a CRM contact.
    @ViewBuilder
    private func rowContent(for call: RecentCall) -> some View {
        if let contactId = call.contactId, !contactId.isEmpty {
            NavigationLink {
                ContactDetailView(
                    contact: stubContact(id: contactId, name: call.contactName, phone: call.phoneNumber),
                    onMessage: {}
                )
            } label: {
                recentRow(call)
            }
        } else {
            recentRow(call)
        }
    }

    private func recentRow(_ call: RecentCall) -> some View {
        // BOREAL_DIALER_v803_UI - mockup row: 44pt avatar, round outlined call button.
        HStack(spacing: 13) {
            AvatarCircle(name: call.title, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(call.title)
                    .rowTitle()
                    .foregroundColor(call.missed ? Theme.red : Theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: call.isInbound ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundColor(call.missed ? Theme.red : Theme.muted)
                    Text(call.subtitle).rowSubtitle().lineLimit(1)
                }
            }

            Spacer()

            if let number = call.phoneNumber, !number.isEmpty {
                RoundIconButton(systemImage: "phone.fill", accessibility: "Call back") {
                    CallManager.shared.startCall(to: number)
                }
            }
        }
        .padding(.vertical, 5)
        .listRowBackground(Color.clear)
        // BOREAL_DIALER_v821 - the row detail: long-press a call for its summary and next steps.
        .contextMenu {
            if call.summaryRef != nil {
                Button {
                    summaryFor = call
                } label: {
                    Label("Call summary", systemImage: "sparkles")
                }
            }
        }
    }
}

// MARK: - Voicemail

struct Voicemail: Identifiable, Decodable {
    let id: String
    let recordingUrl: String?
    let callSid: String?
    let createdAt: String?
    let contactId: String?
    let contactName: String?
    let contactPhone: String?
    // BOREAL_DIALER_VOICEMAIL_DETAIL_v29
    let durationSeconds: Int?
    let transcript: String?

    enum CodingKeys: String, CodingKey {
        case id
        case recordingUrl = "recording_url"
        case callSid = "call_sid"
        case createdAt = "created_at"
        case contactId = "contact_id"
        case contactName = "contact_name"
        case contactPhone = "contact_phone"
        case durationSeconds = "duration_seconds"
        case transcript
    }

    // "0:34", as in the concept mockup.
    var durationLabel: String? {
        guard let seconds = durationSeconds, seconds > 0 else { return nil }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var title: String {
        contactName ?? PhoneFormat.display(contactPhone).ifEmpty("Unknown caller")
    }

    var subtitle: String {
        guard let date = CalendarFormatters.parse(createdAt) else { return "" }
        return CalendarFormatters.time.string(from: date)
    }
}

private struct VoicemailEnvelope: Decodable { let data: [Voicemail] }

@MainActor
final class VoicemailViewModel: ObservableObject {
    @Published var voicemails: [Voicemail] = []
    @Published var loading = false
    @Published var playingId: String?
    @Published var error: String?

    private var player: AVAudioPlayer?

    var grouped: [(String, [Voicemail])] {
        var order: [String] = []
        var buckets: [String: [Voicemail]] = [:]
        for item in voicemails {
            let key = DayBucket.label(for: item.createdAt)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    func load() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/crm/voicemails")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            voicemails = try JSONDecoder().decode(VoicemailEnvelope.self, from: data).data
        } catch {
            self.error = "Could not load voicemail."
        }
        loading = false
    }

    // The audio endpoint proxies Twilio with the account credentials and needs
    // the staff JWT in the Authorization header, which AVPlayer cannot set on a
    // remote URL. Fetch the bytes through APIClient and play them from disk.
    func play(_ voicemail: Voicemail) async {
        if playingId == voicemail.id {
            stop()
            return
        }
        stop()
        error = nil
        // BOREAL_DIALER_v817_CALLS - voicemail switches the shared audio
        // session to .playback, which cut the microphone out of a live call.
        guard Self.noCallActive else {
            self.error = "Voicemail can't play during a call."
            return
        }
        do {
            let request = try APIClient.shared.makeRequest(path: "/crm/voicemails/\(voicemail.id)/audio")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vm-\(voicemail.id).mp3")
            try data.write(to: url, options: .atomic)

            // BOREAL_DIALER_v817_CALLS - a call may have started during the download.
            guard Self.noCallActive else {
                self.error = "Voicemail can't play during a call."
                return
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            // BOREAL_DIALER_v817_CALLS - hand the session back when it finishes.
            audioPlayer.delegate = finishObserver
            audioPlayer.play()
            player = audioPlayer
            playingId = voicemail.id
        } catch {
            self.error = "Couldn't play that voicemail."
            restoreCallAudio()
        }
    }

    func stop() {
        let wasPlaying = player != nil
        player?.stop()
        player = nil
        playingId = nil
        if wasPlaying { restoreCallAudio() }
    }

    // BOREAL_DIALER_v817_CALLS - the player finished on its own.
    private lazy var finishObserver: VoicemailFinishObserver = VoicemailFinishObserver { [weak self] in
        Task { @MainActor in self?.stop() }
    }

    private static var noCallActive: Bool {
        VoiceEngine.shared.isIdle && CallStateManager.shared.current() == .idle
    }

    // BOREAL_DIALER_v817_CALLS - release the playback session and put the call
    // category back, so the next call starts on .playAndRecord/.voiceChat.
    // Never touched while a call is up: CallKit owns the session then.
    private func restoreCallAudio() {
        guard Self.noCallActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        TwilioVoiceManager.shared.configureAudioSessionForCall()
    }
}

// BOREAL_DIALER_v817_CALLS - AVAudioPlayer's delegate must be an NSObject.
private final class VoicemailFinishObserver: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish()
    }
}

struct VoicemailView: View {
    @StateObject private var viewModel = VoicemailViewModel()
    // BOREAL_DIALER_v821 - set by a tapped VOICEMAIL alert (its voicemailId); opened once the list has it.
    @Binding var focusId: String?
    @State private var opened: Voicemail?

    var body: some View {
        // BOREAL_DIALER_CALLS_TAP_THROUGH_v35
        NavigationStack {
        Group {
            if viewModel.loading && viewModel.voicemails.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.voicemails.isEmpty {
                Text(viewModel.error ?? "No voicemail")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let error = viewModel.error {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }
                    ForEach(viewModel.grouped, id: \.0) { day, items in
                        Section {
                            ForEach(items) { voicemail in
                                HStack(spacing: 12) {
                                    Button {
                                        Task { await viewModel.play(voicemail) }
                                    } label: {
                                        Image(systemName: viewModel.playingId == voicemail.id
                                              ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.title2)
                                    }
                                    .buttonStyle(.plain)

                                    AvatarCircle(name: voicemail.title, size: 40) // BOREAL_DIALER_v803_UI

                                    // BOREAL_DIALER_CALLS_TAP_THROUGH_v35 - the
                                    // play button owns the row, so the name is
                                    // the navigable part.
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let contactId = voicemail.contactId, !contactId.isEmpty {
                                            NavigationLink {
                                                ContactDetailView(
                                                    contact: stubContact(
                                                        id: contactId,
                                                        name: voicemail.contactName,
                                                        phone: voicemail.contactPhone
                                                    ),
                                                    onMessage: {}
                                                )
                                            } label: {
                                                Text(voicemail.title)
                                                    .font(.system(size: 15.5, weight: .semibold))
                                                    .foregroundColor(Theme.text)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            Text(voicemail.title)
                                                .font(.system(size: 15.5, weight: .semibold))
                                        }
                                        Text(voicemail.subtitle)
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.muted)
                                        // Nothing writes transcript today -
                                        // Twilio transcription is off - so this
                                        // only appears if it is switched on.
                                        if let transcript = voicemail.transcript,
                                           !transcript.trimmingCharacters(in: .whitespaces).isEmpty {
                                            Text("Transcript: \u{201C}\(transcript)\u{201D}")
                                                .font(.system(size: 13))
                                                .foregroundColor(Theme.faint)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    if let duration = voicemail.durationLabel {
                                        Text(duration)
                                            .font(.system(size: 12).monospacedDigit())
                                            .foregroundColor(Theme.faint)
                                    }

                                    if let phone = voicemail.contactPhone, !phone.isEmpty {
                                        Button {
                                            CallManager.shared.startCall(to: phone)
                                        } label: {
                                            Image(systemName: "phone.fill")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            SectionLabel(text: day)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .refreshable { await viewModel.load() }
            }
        }
        .toolbar(.hidden, for: .navigationBar) // BOREAL_DIALER_v803_UI - no empty bar above the list
        }
        .task {
            await viewModel.load()
            openFocused() // BOREAL_DIALER_v821
        }
        .onChange(of: focusId) { _ in
            Task { @MainActor in
                // An alert for a voicemail the list does not have yet: reload once, then open it.
                if let id = focusId, !viewModel.voicemails.contains(where: { $0.id == id }) {
                    await viewModel.load()
                }
                openFocused()
            }
        }
        .sheet(item: $opened) { voicemail in
            VoicemailDetailSheet(voicemail: voicemail, viewModel: viewModel)
        }
        .onDisappear { viewModel.stop() }
    }

    // BOREAL_DIALER_v821
    private func openFocused() {
        guard let id = focusId else { return }
        focusId = nil
        if let match = viewModel.voicemails.first(where: { $0.id == id }) {
            opened = match
        } else {
            viewModel.error = "That voicemail is no longer available."
        }
    }
}

// BOREAL_DIALER_v821 - one voicemail: who, when, the full transcript, play, call back and the contact.
struct VoicemailDetailSheet: View {
    let voicemail: Voicemail
    @ObservedObject var viewModel: VoicemailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        AvatarCircle(name: voicemail.title, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voicemail.title).rowTitle()
                            Text([voicemail.subtitle, voicemail.durationLabel ?? ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .rowSubtitle()
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    if let transcript = voicemail.transcript,
                       !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(transcript)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.text)
                            .textSelection(.enabled)
                    } else {
                        Text("No transcript for this voicemail.")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.muted)
                    }
                } header: {
                    SectionLabel(text: "Transcript")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button {
                        Task { await viewModel.play(voicemail) }
                    } label: {
                        Label(viewModel.playingId == voicemail.id ? "Stop" : "Play voicemail",
                              systemImage: viewModel.playingId == voicemail.id ? "stop.circle.fill" : "play.circle.fill")
                    }
                    if let phone = voicemail.contactPhone, !phone.isEmpty {
                        Button {
                            viewModel.stop()
                            dismiss()
                            CallManager.shared.startCall(to: phone)
                        } label: {
                            Label("Call back", systemImage: "phone.fill")
                        }
                    }
                    if let contactId = voicemail.contactId, !contactId.isEmpty {
                        NavigationLink {
                            ContactDetailView(
                                contact: stubContact(id: contactId, name: voicemail.contactName, phone: voicemail.contactPhone),
                                onMessage: {}
                            )
                        } label: {
                            Label("Open contact", systemImage: "person.crop.circle")
                        }
                    }
                    if let error = viewModel.error {
                        Text(error).font(.footnote).foregroundColor(Theme.red)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Voicemail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.stop()
                        dismiss()
                    }
                }
            }
        }
    }
}
