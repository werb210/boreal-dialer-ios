// BOREAL_DIALER_CONTACT_DETAIL_v30
// Tapping a contact did nothing at all - the rows were inert, which is most of
// why the app felt like it had no interactions. This is the record: who they
// are, the three actions, and the activity the portal already logs.
//
//   GET /api/crm/contacts/:id/timeline
//     -> { success, data: [ { kind, id, ts, title, body, extra } ] }
//
// kind is one of note, task, call, email, meeting, recording. The timeline is
// silo-scoped server-side from X-Silo, so switching line re-scopes it.
import SwiftUI

struct TimelineEntry: Identifiable, Decodable {
    let kind: String?
    let id: String
    let ts: String?
    let title: String?
    let body: String?
    let extra: String?

    var icon: String {
        switch (kind ?? "").lowercased() {
        case "call": return "phone.fill"
        // BOREAL_DIALER_BI_ACTIVITY_v52 - bi-server also emits sms and demo.
        case "sms": return "message.fill"
        case "demo": return "person.2.fill"
        case "email": return "envelope.fill"
        case "note": return "note.text"
        case "task": return "checkmark.circle"
        case "meeting": return "calendar"
        case "recording": return "waveform"
        default: return "circle"
        }
    }

    var heading: String {
        if let title, !title.isEmpty { return title }
        return (kind ?? "Activity").capitalized
    }

    var timeLabel: String {
        guard let date = CalendarFormatters.parse(ts) else { return "" }
        return "\(DayBucket.label(for: ts)) · \(CalendarFormatters.time.string(from: date))"
    }
}

private struct TimelineEnvelope: Decodable {
    let data: [TimelineEntry]
}

@MainActor
final class ContactDetailViewModel: ObservableObject {
    @Published var entries: [TimelineEntry] = []
    @Published var loading = false
    @Published var error: String?

    // BOREAL_DIALER_BI_ACTIVITY_v52 - a BI contact's activity lives in
    // bi_contact_activity on bi-pg01, so BF-Server's timeline endpoint returns
    // nothing for it. Calls and SMS placed from this app still log to
    // BF-Server, so a BI contact's phone activity will NOT appear here yet -
    // the staff portal merges both sources and this does not.
    func load(contactId: String, silo: Silo) async {
        loading = true
        do {
            if silo == .bi {
                entries = try await BIDirectory.activity(contactId: contactId)
            } else {
                let request = try APIClient.shared.makeRequest(
                    path: "/crm/contacts/\(contactId)/timeline"
                )
                let data = try await APIClient.shared.makeAuthorizedRequest(request)
                entries = try JSONDecoder().decode(TimelineEnvelope.self, from: data).data
            }
            self.error = nil
        } catch {
            self.error = "Could not load activity."
        }
        loading = false
    }
}

struct ContactDetailView: View {
    let contact: CRMContact
    // BOREAL_DIALER_BI_ACTIVITY_v52 - defaulted so the BF call sites are
    // unchanged; the Contacts list passes its own selection through.
    var silo: Silo = .bf
    var onMessage: () -> Void

    @StateObject private var viewModel = ContactDetailViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    AvatarCircle(name: contact.displayName, size: 76)
                    Text(contact.displayName)
                        .font(.system(size: 22, weight: .semibold))
                    if let company = contact.companyName, !company.isEmpty {
                        Text(company)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.muted)
                    }
                    if let status = contact.leadStatus, !status.isEmpty {
                        Text(status)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.line2, lineWidth: 1)
                            )
                            .foregroundColor(Theme.muted)
                    }
                }
                .padding(.top, 20)

                HStack(spacing: 28) {
                    if let phone = contact.callablePhone {
                        ActionButton(icon: "phone.fill", label: "Call") {
                            CallManager.shared.startCall(to: phone)
                        }
                        ActionButton(icon: "message.fill", label: "Message", action: onMessage)
                    }
                    if let email = contact.emailAddress,
                       let url = URL(string: "mailto:\(email)") {
                        ActionButton(icon: "envelope.fill", label: "Email") { openURL(url) }
                    }
                }

                VStack(spacing: 0) {
                    if let phone = contact.callablePhone {
                        DetailRow(label: "Mobile", value: PhoneFormat.display(phone))
                    }
                    if let email = contact.emailAddress {
                        DetailRow(label: "Email", value: email)
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Activity")
                        .padding(.horizontal, 16)

                    if viewModel.loading && viewModel.entries.isEmpty {
                        ProgressView().padding()
                    } else if viewModel.entries.isEmpty {
                        Text(viewModel.error ?? "No activity yet.")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.muted)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.entries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.icon)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.muted)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.heading)
                                        .font(.system(size: 14, weight: .medium))
                                    if let body = entry.body, !body.isEmpty {
                                        Text(body)
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.muted)
                                            .lineLimit(3)
                                    }
                                    Text(entry.timeLabel)
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.faint)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 7)
                        }
                    }
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(contactId: contact.id, silo: silo) }
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.surface2))
                    .foregroundColor(Theme.green)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
