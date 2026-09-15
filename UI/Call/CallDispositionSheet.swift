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
