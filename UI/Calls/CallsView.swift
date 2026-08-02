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

struct CallsView: View {
    // BOREAL_DIALER_UIKIT_AND_SECTION_v13 - not `Section`: that shadows
    // SwiftUI.Section throughout this type.
    enum CallSection: String, CaseIterable {
        case keypad = "Keypad"
        case recents = "Recents"
        case voicemail = "Voicemail"
    }

    @State private var section: CallSection = .keypad

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(CallSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch section {
            case .keypad:
                // BOREAL_DIALER_QUICK_CALL_v16
                VStack(spacing: 0) {
                    QuickCallRow()
                    Divider().padding(.top, 8)
                    DialerView()
                }
            case .recents: RecentCallsView()
            case .voicemail: VoicemailView()
            }
        }
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

    enum CodingKeys: String, CodingKey {
        case id, direction, status
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case phoneNumber = "phone_number"
        case contactId = "contact_id"
        case contactName = "contact_name"
    }

    var isInbound: Bool { (direction ?? "").lowercased() == "inbound" }
    var missed: Bool {
        let s = (status ?? "").lowercased()
        return isInbound && (s == "no-answer" || s == "missed" || s == "busy" || s == "failed")
    }

    var title: String { contactName ?? phoneNumber ?? "Unknown" }

    var subtitle: String {
        var parts: [String] = [isInbound ? "Incoming" : "Outgoing"]
        if let date = CalendarFormatters.parse(createdAt) {
            parts.append(CalendarFormatters.time.string(from: date))
        }
        if let seconds = durationSeconds, seconds > 0 {
            parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
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

    func load() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/voice/recent-calls")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            calls = try JSONDecoder().decode(RecentCallsEnvelope.self, from: data).items
        } catch {
            self.error = "Could not load recent calls."
        }
        loading = false
    }
}

struct RecentCallsView: View {
    @StateObject private var viewModel = RecentCallsViewModel()

    var body: some View {
        Group {
            if viewModel.loading && viewModel.calls.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.calls.isEmpty {
                Text(viewModel.error ?? "No recent calls")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.calls) { call in
                    HStack(spacing: 12) {
                        Image(systemName: call.isInbound
                              ? (call.missed ? "phone.arrow.down.left" : "phone.arrow.down.left")
                              : "phone.arrow.up.right")
                            .foregroundColor(call.missed ? .red : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(call.title)
                                .font(.body)
                                .foregroundColor(call.missed ? .red : .primary)
                            Text(call.subtitle).font(.caption).foregroundColor(.secondary)
                        }

                        Spacer()

                        if let number = call.phoneNumber, !number.isEmpty {
                            Button {
                                CallManager.shared.startCall(to: number)
                            } label: {
                                Image(systemName: "phone.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
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

    enum CodingKeys: String, CodingKey {
        case id
        case recordingUrl = "recording_url"
        case callSid = "call_sid"
        case createdAt = "created_at"
        case contactId = "contact_id"
        case contactName = "contact_name"
        case contactPhone = "contact_phone"
    }

    var title: String { contactName ?? contactPhone ?? "Unknown caller" }

    var subtitle: String {
        guard let date = CalendarFormatters.parse(createdAt) else { return "" }
        return "\(CalendarFormatters.day.string(from: date)) · \(CalendarFormatters.time.string(from: date))"
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
        do {
            let request = try APIClient.shared.makeRequest(path: "/crm/voicemails/\(voicemail.id)/audio")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vm-\(voicemail.id).mp3")
            try data.write(to: url, options: .atomic)

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.play()
            player = audioPlayer
            playingId = voicemail.id
        } catch {
            self.error = "Couldn't play that voicemail."
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingId = nil
    }
}

struct VoicemailView: View {
    @StateObject private var viewModel = VoicemailViewModel()

    var body: some View {
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
                    ForEach(viewModel.voicemails) { voicemail in
                        HStack(spacing: 12) {
                            Button {
                                Task { await viewModel.play(voicemail) }
                            } label: {
                                Image(systemName: viewModel.playingId == voicemail.id
                                      ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(voicemail.title).font(.body)
                                Text(voicemail.subtitle).font(.caption).foregroundColor(.secondary)
                            }

                            Spacer()

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
                }
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.stop() }
    }
}
