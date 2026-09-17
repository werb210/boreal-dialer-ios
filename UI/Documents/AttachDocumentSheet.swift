import SwiftUI

// BOREAL_DIALER_SHARE_TO_BOREAL_v319 - choose contact, application and category, then upload.
struct ContactApplicationRow: Identifiable, Decodable {
    let id: String
    let stage: String?
}

struct AttachDocumentSheet: View {
    let file: SharedFile
    let onDone: () -> Void

    @State private var query = ""
    @State private var contacts: [CRMContact] = []
    @State private var contact: CRMContact?
    @State private var applications: [ContactApplicationRow] = []
    @State private var application: ContactApplicationRow?
    @State private var category = SharedDocumentInbox.categories[0]
    @State private var busy = false
    @State private var message: String?
    @State private var uploaded = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    Label(file.name, systemImage: "doc")
                }
                if contact == nil {
                    Section("Client") {
                        TextField("Search name, business or phone", text: $query)
                            .textInputAutocapitalization(.never)
                            .onChange(of: query) { _ in search() }
                        ForEach(contacts) { row in
                            Button {
                                contact = row
                                Task { await loadApplications(for: row) }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(row.displayName)
                                    if let company = row.companyName { Text(company).font(.caption).foregroundColor(.secondary) }
                                }
                            }
                        }
                    }
                } else if let contact {
                    Section("Client") {
                        HStack {
                            Text(contact.displayName)
                            Spacer()
                            Button("Change") { self.contact = nil; application = nil; applications = [] }
                        }
                    }
                    Section("Application") {
                        if applications.isEmpty {
                            Text(busy ? "Loading…" : "This client has no applications.").foregroundColor(.secondary)
                        }
                        ForEach(applications) { app in
                            Button {
                                application = app
                            } label: {
                                HStack {
                                    Text(Self.applicationLabel(app))
                                    Spacer()
                                    if application?.id == app.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("Category") {
                        Picker("Category", selection: $category) {
                            ForEach(SharedDocumentInbox.categories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                if let message {
                    Section { Text(message).foregroundColor(uploaded ? .green : .red) }
                }
            }
            .navigationTitle("Add to application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uploaded ? "Done" : "Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Uploading…" : "Upload") { Task { await upload() } }
                        .disabled(busy || uploaded || application == nil)
                }
            }
        }
    }

    static func applicationLabel(_ app: ContactApplicationRow) -> String {
        let stage = (app.stage ?? "").replacingOccurrences(of: "_", with: " ")
        let short = String(app.id.prefix(8))
        return stage.isEmpty ? "Application \(short)" : "Application \(short) · \(stage.capitalized)"
    }

    private func search() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { contacts = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                  let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            do {
                let request = try APIClient.shared.makeRequest(path: "/crm/contacts?pageSize=25&q=\(encoded)", silo: .bf)
                let data = try await APIClient.shared.makeAuthorizedRequest(request)
                contacts = try JSONDecoder().decode(ContactsListEnvelope.self, from: data).data
            } catch {
                contacts = []
            }
        }
    }

    private func loadApplications(for contact: CRMContact) async {
        busy = true
        defer { busy = false }
        do {
            let request = try APIClient.shared.makeRequest(path: "/crm/contacts/\(contact.id)/applications", silo: .bf)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            applications = try JSONDecoder().decode([ContactApplicationRow].self, from: data)
            if applications.count == 1 { application = applications[0] }
        } catch {
            applications = []
            message = "Could not load this client's applications."
        }
    }

    private func upload() async {
        guard let application else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let fileData = try Data(contentsOf: file.url)
            let boundary = "Boundary-\(UUID().uuidString)"
            let body = SharedDocumentInbox.multipartBody(applicationId: application.id, category: category, file: file, fileData: fileData, boundary: boundary)
            let base = try APIClient.shared.makeRequest(path: "/documents/upload", method: "POST", body: body,
                                                        headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"], silo: .bf)
            let request = APIClient.shared.authorizedRequest(base)
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300:
                uploaded = true
                message = "Uploaded to \(contact?.displayName ?? "the application") as \(category)."
            case 409:
                uploaded = true
                message = "This file is already on that application."
            default:
                message = "Upload failed (\(status)). Please try again."
            }
        } catch {
            message = OfflineQueue.isOffline(error) ? "No signal. Try again when you're back online." : "Upload failed. Please try again."
        }
    }
}
