import SwiftUI
import CoreData

struct CallHistoryView: View {

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CallEntity.startedAt, ascending: false)],
        animation: .default
    )
    private var calls: FetchedResults<CallEntity>

    var body: some View {
        List(calls, id: \.id) { call in
            NavigationLink {
                CallDetailView(call: call)
            } label: {
                VStack(alignment: .leading) {
                    Text(call.number)
                        .font(.headline)
                    Text(call.status)
                        .font(.subheadline)
                    Text(call.startedAt.formatted())
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Call History")
    }
}

struct CallDetailView: View {
    let call: CallEntity
    @State private var transcript: String? = nil
    @State private var loadingTranscript = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Call summary
                Group {
                    LabeledContent("Number", value: call.number)
                    LabeledContent("Duration", value: formatDuration(callDurationSeconds))
                    LabeledContent("Outcome", value: call.status)
                    LabeledContent("Date", value: call.startedAt.formatted())
                }
                .padding(.horizontal)

                Divider()

                // Transcript section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Call Transcript")
                        .font(.headline)
                        .padding(.horizontal)

                    if loadingTranscript {
                        ProgressView()
                            .padding()
                    } else if let transcript {
                        Text(transcript)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    } else {
                        Text("No transcript available for this call.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Call Detail")
        .onAppear { fetchTranscript() }
    }

    private var callDurationSeconds: Int? {
        guard let endedAt = call.endedAt else { return nil }
        return Int(max(0, endedAt.timeIntervalSince(call.startedAt)))
    }

    private func fetchTranscript() {
        let callSid = call.id
        guard !callSid.isEmpty else { return }
        loadingTranscript = true

        Task {
            guard let url = URL(string: "\(APIConfig.baseURL)/calls/\(callSid)/transcript") else { return }
            var request = URLRequest(url: url)
            if let token = TokenStorage.shared.getToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            if let (data, _) = try? await URLSession.shared.data(for: request),
               let json = try? JSONDecoder().decode([String: String].self, from: data) {
                await MainActor.run {
                    transcript = json["transcript"]
                    loadingTranscript = false
                }
            } else {
                await MainActor.run { loadingTranscript = false }
            }
        }
    }

    private func formatDuration(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
