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

// BOREAL_DIALER_SMS_BROADCAST_v20 - shared with the broadcast picker, which
// reads the same /crm/contacts response.
struct ContactsListEnvelope: Decodable {
    let data: [CRMContact]
}

// BOREAL_DIALER_CONTACTS_PRESENTATION_v24
// Companies are listed next to people, as in the concept mockup. They come from
// GET /api/companies (mounted at /companies, not under /crm), which returns the
// company row plus a contact_count.
struct CRMCompany: Identifiable, Decodable {
    let id: String
    let name: String?
    let contactCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case contactCount = "contact_count"
    }

    var displayName: String { name ?? "Unnamed company" }

    var subtitle: String {
        let count = contactCount ?? 0
        return count == 1 ? "Company · 1 contact" : "Company · \(count) contacts"
    }
}

private struct CompaniesEnvelope: Decodable {
    let data: [CRMCompany]
}

// One row type so people and companies interleave alphabetically.
enum DirectoryRow: Identifiable {
    case person(CRMContact)
    case company(CRMCompany)

    var id: String {
        switch self {
        case .person(let c): return "p-\(c.id)"
        case .company(let c): return "c-\(c.id)"
        }
    }

    var sortName: String {
        switch self {
        case .person(let c): return c.displayName
        case .company(let c): return c.displayName
        }
    }

    var sectionLetter: String {
        let first = sortName.trimmingCharacters(in: .whitespaces).first
        guard let first, first.isLetter else { return "#" }
        return String(first).uppercased()
    }
}

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [CRMContact] = []
    // BOREAL_DIALER_CONTACTS_PRESENTATION_v24
    @Published var companies: [CRMCompany] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?

    private var searchTask: Task<Void, Never>?

    var totalCount: Int { contacts.count + companies.count }

    // Alphabetical sections, people and companies merged.
    var sections: [(String, [DirectoryRow])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        var rows: [DirectoryRow] = contacts.map { .person($0) }
        rows += companies
            .filter { trimmed.isEmpty || $0.displayName.lowercased().contains(trimmed) }
            .map { .company($0) }

        let sorted = rows.sorted {
            $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending
        }

        var order: [String] = []
        var buckets: [String: [DirectoryRow]] = [:]
        for row in sorted {
            let key = row.sectionLetter
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(row)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

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
            contacts = try JSONDecoder().decode(ContactsListEnvelope.self, from: data).data
            self.error = nil
        } catch {
            self.error = "Could not load contacts."
        }
        // BOREAL_DIALER_CONTACTS_PRESENTATION_v24 - companies are a separate
        // endpoint; a failure there should not empty the people list.
        await loadCompanies()
        loading = false
    }

    private func loadCompanies() async {
        do {
            let request = try APIClient.shared.makeRequest(path: "/companies")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            companies = try JSONDecoder().decode(CompaniesEnvelope.self, from: data).data
        } catch {
            companies = []
        }
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
    // BOREAL_DIALER_CREATE_CONTACT_v34
    @State private var showNewContact = false

    var body: some View {
        // BOREAL_DIALER_CONTACT_DETAIL_v30 - rows push a record now.
        NavigationStack {
        VStack(spacing: 0) {
            // BOREAL_DIALER_CONTACTS_PRESENTATION_v24
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Contacts").font(.headline)
                    Text("Synced from CRM · \(viewModel.totalCount)")
                        .font(.caption).foregroundColor(Theme.muted)
                }
                Spacer()
                // BOREAL_DIALER_CREATE_CONTACT_v34
                Button {
                    showNewContact = true
                } label: {
                    Text("+ New")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search contacts & companies", text: $viewModel.query)
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
                List {
                    ForEach(viewModel.sections, id: \.0) { letter, rows in
                        Section {
                            ForEach(rows) { row in
                                switch row {
                                case .person(let contact):
                                    NavigationLink {
                                        ContactDetailView(contact: contact) {
                                            smsRecipient = contact
                                        }
                                    } label: {
                                        ContactRow(contact: contact) { smsRecipient = contact }
                                    }
                                case .company(let company):
                                    CompanyRow(company: company)
                                }
                            }
                        } header: {
                            SectionLabel(text: letter)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .refreshable { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $smsRecipient) { contact in
            SMSComposeSheet(contact: contact)
        }
        .sheet(isPresented: $showNewContact) {
            NewContactView {
                Task { await viewModel.load() }
            }
        }
        }
    }
}

private struct ContactRow: View {
    let contact: CRMContact
    let onMessage: () -> Void
    // BOREAL_DIALER_UIKIT_AND_SECTION_v13 - replaced the UIKit application
    // singleton with SwiftUI’s native URL-opening environment action.
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(name: contact.displayName, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName).rowTitle()
                if let company = contact.companyName, !company.isEmpty {
                    Text(company).rowSubtitle()
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
                    openURL(url)
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


// BOREAL_DIALER_CONTACTS_PRESENTATION_v24
private struct CompanyRow: View {
    let company: CRMCompany

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(name: company.displayName, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(company.displayName).font(.body.weight(.semibold))
                Text(company.subtitle).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "building.2")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
