// BOREAL_DIALER_SMS_BROADCAST_v20
// Multi-send: pick several contacts and send each of them the same message
// individually. This is NOT a group thread and NOT a marketing blast - the
// server loops the recipients and sends one Twilio message per contact, then
// writes each one to that contact's own timeline.
//
//   POST /api/communications/broadcast { contactIds, body, channel: "sms" }
//     -> { sent, failed, results: [{ contactId, ok, error? }] }
//
// The server caps the list at 500, de-duplicates, and rejects anything that is
// not a contact uuid. It merges tokens per recipient, so the same body can
// address each person by name.
//
// Recipients are restricted to contacts with a phone number: the server records
// those without one as a `no_phone` failure, which is a worse experience than
// simply not offering them.
import SwiftUI

private struct BroadcastResult: Decodable {
    let contactId: String
    let ok: Bool
    let error: String?
}

private struct BroadcastResponse: Decodable {
    let sent: Int
    let failed: Int
    let results: [BroadcastResult]
}

@MainActor
final class SMSBroadcastViewModel: ObservableObject {
    @Published var contacts: [CRMContact] = []
    @Published var selected: Set<String> = []
    @Published var query = ""
    @Published var messageBody = ""
    @Published var loading = false
    @Published var sending = false
    @Published var status: String?
    @Published var error: String?

    private var searchTask: Task<Void, Never>?

    var reachable: [CRMContact] {
        contacts.filter { $0.callablePhone != nil }
    }

    func load() async {
        loading = true
        do {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            var path = "/crm/contacts?pageSize=200"
            if !trimmed.isEmpty,
               let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&q=\(encoded)"
            }
            let request = try APIClient.shared.makeRequest(path: path)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            contacts = try JSONDecoder().decode(ContactsListEnvelope.self, from: data).data
            self.error = nil
        } catch {
            self.error = "Could not load contacts."
        }
        loading = false
    }

    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func toggle(_ contact: CRMContact) {
        if selected.contains(contact.id) {
            selected.remove(contact.id)
        } else {
            selected.insert(contact.id)
        }
    }

    func send() async {
        let text = messageBody.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !selected.isEmpty else { return }
        sending = true
        status = nil
        self.error = nil
        do {
            let payload: [String: Any] = [
                "contactIds": Array(selected),
                "body": text,
                "channel": "sms",
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let request = try APIClient.shared.makeRequest(
                path: "/communications/broadcast", method: "POST", body: body
            )
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let response = try JSONDecoder().decode(BroadcastResponse.self, from: data)

            // Partial success is the normal case on a list of this shape, so
            // report both halves rather than a flat "sent".
            if response.failed == 0 {
                status = "Sent to \(response.sent)."
                selected.removeAll()
                messageBody = ""
            } else {
                status = "Sent to \(response.sent). \(response.failed) failed."
            }
        } catch {
            self.error = "Couldn't send the broadcast."
        }
        sending = false
    }
}

struct SMSBroadcastView: View {
    @StateObject private var viewModel = SMSBroadcastViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Message", text: $viewModel.messageBody, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 8)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search contacts", text: $viewModel.query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.query) { _ in viewModel.queryChanged() }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.vertical, 8)

                if let status = viewModel.status {
                    Text(status).font(.footnote).foregroundColor(.secondary)
                        .padding(.horizontal).padding(.bottom, 4)
                }
                if let error = viewModel.error {
                    Text(error).font(.footnote).foregroundColor(.red)
                        .padding(.horizontal).padding(.bottom, 4)
                }

                Divider()

                if viewModel.loading && viewModel.reachable.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.reachable.isEmpty {
                    Text("No contacts with a mobile number")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.reachable) { contact in
                        Button {
                            viewModel.toggle(contact)
                        } label: {
                            HStack {
                                Image(systemName: viewModel.selected.contains(contact.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(viewModel.selected.contains(contact.id) ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.displayName).font(.body)
                                    if let phone = contact.callablePhone {
                                        Text(phone).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Broadcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.selected.isEmpty ? "Send" : "Send (\(viewModel.selected.count))") {
                        Task { await viewModel.send() }
                    }
                    .disabled(
                        viewModel.sending
                        || viewModel.selected.isEmpty
                        || viewModel.messageBody.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
            .task { await viewModel.load() }
        }
    }
}
