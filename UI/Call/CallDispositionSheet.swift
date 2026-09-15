// BOREAL_DIALER_POST_CALL_DISPOSITION_v201
// Shown once a call ends. Deliberately one tap for the common case: pick an
// outcome and it is saved. Skip is always available - a dialog staff cannot
// dismiss is a dialog they will learn to dread, and an unrecorded call is better
// than a wrong one recorded to escape the sheet.
import SwiftUI

struct CallDispositionSheet: View {
    let callRef: String
    let contactName: String?
    let durationText: String?
    var onFinished: (CallDisposition?) -> Void

    @State private var saving: CallDisposition?
    @State private var failure: String?
    // BOREAL_DIALER_CALL_SUMMARY_v246
    @State private var summary: String?
    @State private var summaryUnavailable = false
    // BOREAL_DIALER_SUGGESTED_TASKS_v254
    @State private var suggestions: [SuggestedCallTask] = []
    @State private var suggestionContactId: String?
    @State private var addedSuggestions: Set<String> = []
    @State private var addingSuggestion: String?
    @State private var suggestionError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contactName ?? "Call complete")
                            .font(.headline)
                        if let durationText {
                            Text(durationText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // BOREAL_DIALER_CALL_SUMMARY_v246
                Section("Summary") {
                    if let summary {
                        Text(summary)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    } else if summaryUnavailable {
                        Text("No summary for this call.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Summary will appear once the transcript is ready. It is also saved to the contact.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // BOREAL_DIALER_SUGGESTED_TASKS_v254
                if !suggestions.isEmpty {
                    Section("Suggested follow-ups") {
                        ForEach(suggestions) { task in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                    Text(task.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if addedSuggestions.contains(task.id) {
                                    Label("Added", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.iconOnly)
                                        .foregroundStyle(.green)
                                } else if addingSuggestion == task.id {
                                    ProgressView()
                                } else {
                                    Button("Add") { Task { await addSuggestion(task) } }
                                        .buttonStyle(.bordered)
                                        .disabled(addingSuggestion != nil)
                                }
                            }
                        }
                        if let suggestionError {
                            Text(suggestionError).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }

                Section("How did it go?") {
                    ForEach(CallDisposition.ordered) { option in
                        Button {
                            Task { await save(option) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .foregroundStyle(.primary)
                                    if let note = option.followUpNote {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if saving == option {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(saving != nil)
                    }
                }

                if let failure {
                    Section {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .task { await pollSummary() } // BOREAL_DIALER_CALL_SUMMARY_v246
            .navigationTitle("Call outcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onFinished(nil)
                        dismiss()
                    }
                    .disabled(saving != nil)
                }
            }
        }
    }

    // BOREAL_DIALER_CALL_SUMMARY_v246 - cancelled automatically when the sheet closes.
    private func pollSummary() async {
        var attempt = 0
        var latest: CallSummaryResult?
        while CallSummaryService.shouldKeepPolling(latest, attempt: attempt) {
            attempt += 1
            latest = try? await CallSummaryService.fetch(callSid: callRef)
            if let text = latest?.summary, latest?.status == "ready", !text.isEmpty {
                summary = text
                suggestions = latest?.suggestedTasks ?? [] // BOREAL_DIALER_SUGGESTED_TASKS_v254
                suggestionContactId = latest?.contactId
                return
            }
            if latest?.status == "none" {
                summaryUnavailable = true
                return
            }
            do {
                try await Task.sleep(nanoseconds: CallSummaryService.pollIntervalNanoseconds)
            } catch {
                return
            }
        }
        summaryUnavailable = true
    }

    // BOREAL_DIALER_SUGGESTED_TASKS_v254
    private func addSuggestion(_ task: SuggestedCallTask) async {
        addingSuggestion = task.id
        suggestionError = nil
        do {
            try await SuggestedTaskService.add(task, contactId: suggestionContactId)
            addedSuggestions.insert(task.id)
        } catch {
            suggestionError = "Could not add that task. Try again."
        }
        addingSuggestion = nil
    }

    private func save(_ option: CallDisposition) async {
        saving = option
        failure = nil
        do {
            _ = try await CallDispositionService.record(callRef: callRef, disposition: option)
            onFinished(option)
            dismiss()
        } catch {
            // Stay on the sheet. Losing the outcome because the network blipped
            // is the failure staff would actually notice.
            failure = error.localizedDescription
            saving = nil
        }
    }
}
