// BOREAL_DIALER_SMS_NEW_MESSAGE_v33
// Starting a conversation with someone who has no thread yet. Until now the SMS
// tab could only reply inside an existing thread or broadcast to many, so the
// ordinary case - texting one person for the first time - had nowhere to go.
//
// Sends through POST /api/communications/sms, the same endpoint the thread
// reply uses, so it lands on the contact's timeline. A free-typed number sends
// without a contactId; the server resolves the contact from the number on its
// side, and the thread appears on the next refresh either way.
import SwiftUI

struct SMSTemplate: Decodable, Identifiable {
    let id: String
    let name: String
    let bodyText: String
    let bodyHtml: String?
    let isSnippet: Bool
    let shortcut: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, shortcut
        case bodyText = "body_text"
        case bodyHtml = "body_html"
        case isSnippet = "is_snippet"
    }
}

private struct SMSTemplatesEnvelope: Decodable {
    let templates: [SMSTemplate]

    private enum CodingKeys: String, CodingKey { case templates, data }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([SMSTemplate].self) {
            templates = array
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templates = try container.decodeIfPresent([SMSTemplate].self, forKey: .templates)
            ?? container.decode([SMSTemplate].self, forKey: .data)
    }
}

@MainActor
final class SMSNewMessageViewModel: ObservableObject {
    @Published var contacts: [CRMContact] = []
    @Published var query = ""
    @Published var manualNumber = ""
    @Published var selected: CRMContact?
    @Published var messageBody = ""
    @Published var sending = false
    @Published var error: String?
    @Published private(set) var templates: [SMSTemplate] = []
    @Published private(set) var loadingTemplates = false
    @Published var templateError: String?

    private var searchTask: Task<Void, Never>?

    var reachable: [CRMContact] {
        contacts.filter { $0.callablePhone != nil }
    }

    // A contact wins over a typed number; the number is the fallback for people
    // who are not in the CRM yet.
    var resolvedNumber: String? {
        if let selected, let phone = selected.callablePhone { return phone }
        let digits = manualNumber.filter(\.isNumber)
        return digits.count >= 10 ? manualNumber : nil
    }

    var canSend: Bool {
        !sending
        && resolvedNumber != nil
        && !messageBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func load() async {
        do {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            var path = "/crm/contacts?pageSize=100"
            if !trimmed.isEmpty,
               let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&q=\(encoded)"
            }
            let request = try APIClient.shared.makeRequest(path: path)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            contacts = try JSONDecoder().decode(ContactsListEnvelope.self, from: data).data
        } catch {
            self.error = "Could not load contacts."
        }
    }

    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func loadTemplates() async {
        loadingTemplates = true
        templateError = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/templates?channel=sms")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            templates = try JSONDecoder().decode(SMSTemplatesEnvelope.self, from: data).templates.sorted {
                if $0.isSnippet != $1.isSnippet { return $0.isSnippet }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            templateError = "Could not load templates."
        }
        loadingTemplates = false
    }

    func send() async -> Bool {
        guard let to = resolvedNumber else { return false }
        sending = true
        error = nil
        do {
            try await API.sendSMS(
                SendSMSPayload(to: to, body: messageBody, contactId: selected?.id)
            )
            sending = false
            return true
        } catch {
            self.error = "Couldn't send that message. Please try again."
            sending = false
            return false
        }
    }
}

struct SMSNewMessageView: View {
    var onSent: () -> Void

    @StateObject private var viewModel = SMSNewMessageViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingTemplates = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("To")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)

                    if let selected = viewModel.selected {
                        HStack(spacing: 6) {
                            Text(selected.displayName)
                                .font(.system(size: 14, weight: .semibold))
                            Button {
                                viewModel.selected = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.surface3))
                    } else {
                        TextField("Name or number", text: $viewModel.query)
                            .textFieldStyle(.plain)
                            .keyboardType(.phonePad)
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.query) { value in
                                // Digits mean they are typing a number rather
                                // than searching for a name.
                                viewModel.manualNumber = value
                                viewModel.queryChanged()
                            }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Rectangle().fill(Theme.line).frame(height: 1)

                if viewModel.selected == nil {
                    List(viewModel.reachable) { contact in
                        Button {
                            viewModel.selected = contact
                        } label: {
                            HStack(spacing: 13) {
                                AvatarCircle(name: contact.displayName, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.displayName).rowTitle()
                                    if let phone = contact.callablePhone {
                                        Text(PhoneFormat.display(phone)).rowSubtitle()
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bg)
                } else {
                    Spacer()
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                ComposerBar(
                    placeholder: "Text message…",
                    text: $viewModel.messageBody,
                    disabled: !viewModel.canSend,
                    onTemplates: {
                        showingTemplates = true
                        Task { await viewModel.loadTemplates() }
                    }
                ) {
                    Task {
                        if await viewModel.send() {
                            onSent()
                            dismiss()
                        }
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $showingTemplates) {
                NavigationStack {
                    List {
                        if viewModel.loadingTemplates {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if let error = viewModel.templateError {
                            Text(error).foregroundColor(Theme.red)
                        } else if viewModel.templates.isEmpty {
                            Text("No SMS templates available.").foregroundColor(Theme.muted)
                        } else {
                            ForEach(viewModel.templates) { template in
                                Button {
                                    viewModel.messageBody = template.bodyText
                                    showingTemplates = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(template.name).font(.headline)
                                            if template.isSnippet {
                                                Text("Snippet").font(.caption2).foregroundColor(Theme.green)
                                            }
                                        }
                                        Text(template.bodyText).font(.subheadline).foregroundColor(Theme.muted).lineLimit(3)
                                        if let shortcut = template.shortcut, !shortcut.isEmpty {
                                            Text(shortcut).font(.caption2).foregroundColor(Theme.muted)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .navigationTitle("Templates")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingTemplates = false }
                        }
                    }
                }
            }
        }
    }
}
