// BOREAL_DIALER_CONTACTS_TAB_v7
// The BF silo CRM contact list, read from GET /api/crm/contacts - the same
// endpoint the staff portal's Contacts page uses. The silo is not passed here:
// APIClient stamps X-Silo from the active line, and the server resolves it, so
// switching silo in the line switcher re-scopes this list for free.
//
// The response envelope is { success, data: [...], meta: { page, pageSize,
// total } }, so the rows come out of `data`, not the top level.
import SwiftUI

struct CRMContact: Identifiable, Decodable {
    let id: String
    let name: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let companyName: String?
    let leadStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone
        case firstName = "first_name"
        case lastName = "last_name"
        case companyName = "company_name"
        case leadStatus = "lead_status"
    }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        let joined = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        let trimmed = joined.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return email ?? phone ?? "Unnamed contact"
    }

    var callablePhone: String? {
        guard let phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return phone
    }

    var emailAddress: String? {
        guard let email, email.contains("@") else { return nil }
        return email
    }
}

private struct ContactsEnvelope: Decodable {
    let data: [CRMContact]
}

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [CRMContact] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?

    private var searchTask: Task<Void, Never>?

    func load() async {
        loading = true
        error = nil
        do {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            var path = "/crm/contacts?pageSize=200"
            if !trimmed.isEmpty,
               let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&q=\(encoded)"
            }
            let request = try APIClient.shared.makeRequest(path: path)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            contacts = try JSONDecoder().decode(ContactsEnvelope.self, from: data).data
        } catch {
            self.error = "Could not load contacts."
        }
        loading = false
    }

    // Server-side search, debounced so typing does not fire a request per key.
    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }
}

struct ContactsView: View {
    @StateObject private var viewModel = ContactsViewModel()
    @State private var smsRecipient: CRMContact?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search contacts", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.query) { _ in viewModel.queryChanged() }
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                        viewModel.queryChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if viewModel.loading && viewModel.contacts.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.contacts.isEmpty {
                Text(viewModel.error ?? "No contacts")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.contacts) { contact in
                    ContactRow(contact: contact) { smsRecipient = contact }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $smsRecipient) { contact in
            SMSComposeSheet(contact: contact)
        }
    }
}

private struct ContactRow: View {
    let contact: CRMContact
    let onMessage: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName).font(.body.weight(.semibold))
                if let company = contact.companyName, !company.isEmpty {
                    Text(company).font(.subheadline).foregroundColor(.secondary)
                }
                if let status = contact.leadStatus, !status.isEmpty {
                    Text(status)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if let phone = contact.callablePhone {
                Button {
                    CallManager.shared.startCall(to: phone)
                } label: {
                    Image(systemName: "phone.fill")
                }
                .buttonStyle(.borderless)

                Button(action: onMessage) {
                    Image(systemName: "message.fill")
                }
                .buttonStyle(.borderless)
            }

            if let email = contact.emailAddress, let url = URL(string: "mailto:\(email)") {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Image(systemName: "envelope.fill")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// Sends through POST /api/communications/sms so the message is logged against
// the contact timeline server-side, the same as the portal's SMS tab.
private struct SMSComposeSheet: View {
    let contact: CRMContact
    @Environment(\.dismiss) private var dismiss

    @State private var messageBody = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(contact.displayName).font(.headline)
                if let phone = contact.callablePhone {
                    Text(phone).font(.subheadline).foregroundColor(.secondary)
                }

                TextEditor(text: $messageBody)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3))
                    )

                if let error {
                    Text(error).font(.footnote).foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(sending || messageBody.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func send() {
        guard let phone = contact.callablePhone else {
            error = "This contact has no phone number."
            return
        }
        sending = true
        error = nil
        Task {
            do {
                try await API.sendSMS(
                    SendSMSPayload(to: phone, body: messageBody, contactId: contact.id)
                )
                sending = false
                dismiss()
            } catch {
                sending = false
                self.error = "Couldn't send that message. Please try again."
            }
        }
    }
}
