// BOREAL_DIALER_QUICK_CALL_v16
// The three pinned staff quick-call slots above the keypad, matching the portal
// and the concept mockup.
//
//   GET /api/telephony/quick-call -> { staff: [...], slots: ["<userId>", ...] }
//   PUT /api/telephony/quick-call    { slots: [...] }   (max 3, server-enforced)
//
// Slots are stored server-side on users.quick_call_slots, so the same three
// people follow a staff member between the handset and the portal.
//
// Calling a teammate is an internal VOIP call: POST /api/voice/calls with
// staffIdentity rather than to. The identity is the user id, which is what
// /api/voice/token issues as the client identity.
import SwiftUI

struct QuickCallStaff: Identifiable, Decodable, Hashable {
    let userId: String
    let name: String?
    let identity: String?
    let avatarUrl: String?
    let online: Bool?

    var id: String { userId }
    var displayName: String { name ?? "Staff" }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
}

private struct QuickCallEnvelope: Decodable {
    let staff: [QuickCallStaff]
    let slots: [String]
}

@MainActor
final class QuickCallViewModel: ObservableObject {
    @Published var staff: [QuickCallStaff] = []
    @Published var slots: [String] = []
    @Published var editing = false
    @Published var error: String?

    var pinned: [QuickCallStaff] {
        slots.compactMap { id in staff.first { $0.userId == id } }
    }

    func load() async {
        do {
            let request = try APIClient.shared.makeRequest(path: "/telephony/quick-call")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let decoded = try JSONDecoder().decode(QuickCallEnvelope.self, from: data)
            staff = decoded.staff
            slots = decoded.slots
            error = nil
        } catch {
            self.error = "Could not load quick call."
        }
    }

    func assign(_ member: QuickCallStaff) async {
        var next = slots.filter { $0 != member.userId }
        next.append(member.userId)
        if next.count > 3 { next = Array(next.suffix(3)) }
        await save(next)
    }

    func remove(_ member: QuickCallStaff) async {
        await save(slots.filter { $0 != member.userId })
    }

    private func save(_ next: [String]) async {
        let previous = slots
        slots = next
        do {
            let body = try JSONSerialization.data(withJSONObject: ["slots": next])
            let request = try APIClient.shared.makeRequest(
                path: "/telephony/quick-call", method: "PUT", body: body
            )
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
            error = nil
        } catch {
            // Put the row back rather than showing a pin that did not persist.
            slots = previous
            self.error = "Couldn't save that quick-call slot."
        }
    }

    func call(_ member: QuickCallStaff) async {
        await ConferenceSession.shared.startInternal(staffIdentity: member.userId)
    }
}

struct QuickCallRow: View {
    @StateObject private var viewModel = QuickCallViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quick call")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(viewModel.editing ? "Done" : "Edit") {
                    viewModel.editing.toggle()
                }
                .font(.caption)
            }

            HStack(spacing: 14) {
                ForEach(viewModel.pinned) { member in
                    Button {
                        if viewModel.editing {
                            Task { await viewModel.remove(member) }
                        } else {
                            Task { await viewModel.call(member) }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 46, height: 46)
                                    .overlay(Text(member.initials).font(.caption.weight(.semibold)))
                                if member.online == true {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 11, height: 11)
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                }
                                if viewModel.editing {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            Text(member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.pinned.count < 3 {
                    Menu {
                        ForEach(viewModel.staff.filter { !viewModel.slots.contains($0.userId) }) { member in
                            Button(member.displayName) {
                                Task { await viewModel.assign(member) }
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3]))
                                .frame(width: 46, height: 46)
                                .overlay(Image(systemName: "plus").foregroundColor(.secondary))
                            Text("Add").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }

            if let error = viewModel.error {
                Text(error).font(.caption2).foregroundColor(.red)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .task { await viewModel.load() }
    }
}
