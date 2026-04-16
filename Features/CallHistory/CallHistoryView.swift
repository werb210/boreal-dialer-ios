import SwiftUI

struct CallHistoryView: View {

    @ObservedObject private var store = CallLogStore.shared
    @State private var currentTranscript: String?

    var body: some View {
        List(store.logs) { log in
            VStack(alignment: .leading, spacing: 4) {

                Text(log.direction.capitalized)
                    .font(.headline)

                Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text("\(Int(log.duration))s")
                    .font(.caption)
                    .foregroundColor(.gray)

                if let currentTranscript, log.callSid != nil {
                    Text(currentTranscript)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let callSid = log.callSid else { return }
                Task {
                    await loadTranscript(for: callSid)
                }
            }
        }
    }

    func loadTranscript(for callSid: String) async {
        do {
            let request = try APIClient.shared.authorizedRequest(endpoint: "/calls/\(callSid)/transcript")
            let data = try await APIClient.shared.execute(request)
            let decoded = try JSONDecoder().decode(TranscriptResponse.self, from: data)
            await MainActor.run {
                self.currentTranscript = decoded.transcript
            }
        } catch {
            print("[TRANSCRIPT] Not available for \(callSid):", error)
        }
    }
}
