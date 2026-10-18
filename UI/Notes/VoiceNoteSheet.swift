import AVFoundation
import Speech
import SwiftUI

// BOREAL_DIALER_v823_VOICE_NOTES
// Dictate a note after a call and save it to the client's Boreal timeline (POST /api/crm/contacts/:id/notes {body},
// the same notes the portal shows). Speech is turned into text on the iPhone where the phone supports it; the text
// can be corrected before saving. Opened from the after-call summary, a contact card, the "Boreal Voice Note" control
// (Action Button / Control Center) and Siri ("Record a note in Boreal Dialer").
struct VoiceNoteTarget: Identifiable, Equatable {
    let id = UUID()
    let contactId: String?
    let name: String?

    static func == (lhs: VoiceNoteTarget, rhs: VoiceNoteTarget) -> Bool {
        lhs.contactId == rhs.contactId && lhs.name == rhs.name
    }

    private struct RecentEnvelope: Decodable { let items: [RecentCall] }

    /// The most recent call that is linked to a client.
    static func lastCallClient() async -> VoiceNoteTarget? {
        guard let request = try? APIClient.shared.makeRequest(path: "/voice/recent-calls"),
              let data = try? await APIClient.shared.makeAuthorizedRequest(request),
              let calls = try? JSONDecoder().decode(RecentEnvelope.self, from: data).items else { return nil }
        return target(from: calls)
    }

    static func target(from calls: [RecentCall]) -> VoiceNoteTarget? {
        guard let call = calls.first(where: { ($0.contactId ?? "").isEmpty == false }),
              let contactId = call.contactId else { return nil }
        return VoiceNoteTarget(contactId: contactId, name: call.contactName ?? call.title)
    }
}

enum VoiceNoteAPI {
    static func notesPath(contactId: String) -> String? {
        let id = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 64, id.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else { return nil }
        return "/crm/contacts/\(id)/notes"
    }

    static func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func save(contactId: String, text: String) async throws {
        let body = cleaned(text)
        guard !body.isEmpty, let path = notesPath(contactId: contactId) else { throw URLError(.badURL) }
        let data = try JSONSerialization.data(withJSONObject: ["body": body])
        let request = try APIClient.shared.makeRequest(path: path, method: "POST", body: data)
        _ = try await APIClient.shared.makeAuthorizedRequest(request)
    }
}

@MainActor
final class NoteDictation: ObservableObject {
    @Published var text = ""
    @Published private(set) var recording = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var prefix = ""

    func toggle() async {
        if recording { stop() } else { await start() }
    }

    func start() async {
        error = nil
        guard VoiceEngine.shared.isIdle else {
            error = "Finish the call first, then record your note."
            return
        }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed else {
            error = "Allow Speech Recognition for Boreal Dialer in Settings to dictate notes."
            return
        }
        let micAllowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micAllowed else {
            error = "Allow the microphone for Boreal Dialer in Settings to dictate notes."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-CA")) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            error = "Dictation isn't available right now. You can type the note instead."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            prefix = text.isEmpty ? "" : text + " "

            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            recording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let transcript = result?.bestTranscription.formattedString
                let finished = (result?.isFinal ?? false) || failure != nil
                Task { @MainActor in
                    guard let self else { return }
                    if let transcript { self.text = self.prefix + transcript }
                    if finished { self.stop() }
                }
            }
        } catch {
            self.error = "Couldn't start the microphone. You can type the note instead."
            stop()
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        guard recording else { return }
        recording = false
        // Hand the audio session back for the next call (as voicemail playback does).
        guard VoiceEngine.shared.isIdle else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        TwilioVoiceManager.shared.configureAudioSessionForCall()
    }
}

struct VoiceNoteSheet: View {
    let target: VoiceNoteTarget

    @StateObject private var dictation = NoteDictation()
    @Environment(\.dismiss) private var dismiss
    @State private var contactId: String?
    @State private var contactName: String?
    @State private var query = ""
    @State private var matches: [CRMContact] = []
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let contactName, contactId != nil {
                    HStack {
                        Label(contactName, systemImage: "person.crop.circle")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if target.contactId == nil {
                            Button("Change") { contactId = nil; self.contactName = nil }
                                .font(.system(size: 13))
                        }
                    }
                } else {
                    contactPicker
                }

                TextEditor(text: $dictation.text)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    .accessibilityLabel("Note text")

                Button {
                    Task { await dictation.toggle() }
                } label: {
                    Label(dictation.recording ? "Stop" : "Dictate", systemImage: dictation.recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(dictation.recording ? .red : Theme.green)

                if let message = dictation.error ?? saveError {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dictation.stop(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving || contactId == nil || VoiceNoteAPI.cleaned(dictation.text).isEmpty)
                }
            }
        }
        .onAppear {
            contactId = target.contactId
            contactName = target.name
            // Opened from a control or Siri with a client in mind: start listening straight away.
            if target.contactId != nil { Task { await dictation.start() } }
        }
        .onDisappear { dictation.stop() }
    }

    private var contactPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Which client is this note for?", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
                .onChange(of: query) { _ in Task { await search() } }
            ForEach(matches.prefix(5)) { contact in
                Button {
                    contactId = contact.id
                    contactName = contact.displayName
                    matches = []
                } label: {
                    Text(contact.displayName).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
    }

    private func search() async {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wanted.count >= 2 else { matches = []; return }
        matches = (try? await BorealClientLookup.search(wanted)) ?? []
    }

    private func save() async {
        guard let contactId else { return }
        dictation.stop()
        saving = true
        saveError = nil
        do {
            try await VoiceNoteAPI.save(contactId: contactId, text: dictation.text)
            saving = false
            dismiss()
        } catch {
            saving = false
            saveError = "Couldn't save the note. Check your connection and try again."
        }
    }
}
