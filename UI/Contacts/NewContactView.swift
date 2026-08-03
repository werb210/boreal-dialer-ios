// BOREAL_DIALER_CREATE_CONTACT_v34
// The mockup's "+ New". Creating a CRM contact from the handset - the case
// where you have just got off a call with someone who is not in the system.
//
//   POST /api/crm/contacts { first_name, last_name, email, phone, company_id }
//     -> 201 { ok: true, data: { ...contact } }
//
// The server requires first_name and last_name; it will split a single `name`
// if only that is given, but sending the two fields explicitly avoids guessing
// where a middle name or a two-word surname belongs.
//
// The phone is normalised to E.164 before sending, for the same reason the OTP
// endpoint needed it: everything downstream - Twilio, thread matching, the
// contact lookup on inbound calls - assumes it.
import SwiftUI

@MainActor
final class NewContactViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var phone = ""
    @Published var companyId: String?
    @Published var companies: [CRMCompany] = []
    @Published var saving = false
    @Published var error: String?

    var canSave: Bool {
        !saving
        && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Matches the server's toE164: ten digits are North American, eleven
    // starting with 1 get the plus, anything already E.164 is left alone.
    private func e164(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("+") { return trimmed }
        let digits = trimmed.filter(\.isNumber)
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return digits.isEmpty ? nil : "+\(digits)"
    }

    func loadCompanies() async {
        struct Envelope: Decodable { let data: [CRMCompany] }
        do {
            let request = try APIClient.shared.makeRequest(path: "/companies")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            companies = try JSONDecoder().decode(Envelope.self, from: data).data
        } catch {
            companies = []
        }
    }

    func save() async -> Bool {
        saving = true
        error = nil
        var payload: [String: Any] = [
            "first_name": firstName.trimmingCharacters(in: .whitespaces),
            "last_name": lastName.trimmingCharacters(in: .whitespaces),
        ]
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty { payload["email"] = trimmedEmail }
        if let number = e164(phone) { payload["phone"] = number }
        if let companyId { payload["company_id"] = companyId }

        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let request = try APIClient.shared.makeRequest(
                path: "/crm/contacts", method: "POST", body: body
            )
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
            saving = false
            return true
        } catch {
            // The server returns a field-level error for bad input; without
            // reading the body we can only say it did not save.
            self.error = "Couldn't save that contact. Check the details and try again."
            saving = false
            return false
        }
    }
}

struct NewContactView: View {
    var onSaved: () -> Void

    @StateObject private var viewModel = NewContactViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $viewModel.firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $viewModel.lastName)
                        .textContentType(.familyName)
                } header: {
                    Text("Name")
                }

                Section {
                    TextField("Mobile", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                } header: {
                    Text("Contact")
                }

                if !viewModel.companies.isEmpty {
                    Section {
                        Picker("Company", selection: $viewModel.companyId) {
                            Text("None").tag(String?.none)
                            ForEach(viewModel.companies) { company in
                                Text(company.displayName).tag(String?.some(company.id))
                            }
                        }
                    }
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("New contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .task { await viewModel.loadCompanies() }
        }
    }
}
