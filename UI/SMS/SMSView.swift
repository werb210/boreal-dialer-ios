import SwiftUI

struct SMSMessageRow: Identifiable, Decodable {
    let id: String
    let body: String?
    let direction: String?
    let fromNumber: String?
    let toNumber: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body, direction
        case fromNumber = "from_number"
        case toNumber = "to_number"
        case createdAt = "created_at"
    }
}

@MainActor
final class SMSViewModel: ObservableObject {
    @Published var items: [SMSMessageRow] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do {
            let req = try APIClient.shared.makeRequest(path: "/communications/messages-list")
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            if let rows = try? JSONDecoder().decode([SMSMessageRow].self, from: data) {
                items = rows
            } else {
                struct Resp: Decodable { let items: [SMSMessageRow]? ; let messages: [SMSMessageRow]? }
                let r = try JSONDecoder().decode(Resp.self, from: data)
                items = r.items ?? r.messages ?? []
            }
        } catch {
            self.error = "Could not load SMS."
        }
        loading = false
    }
}

struct SMSView: View {
    @StateObject private var vm = SMSViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("SMS").font(.headline); Spacer() }
                .padding(.horizontal).padding(.vertical, 8)
            Divider()

            if vm.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.items.isEmpty {
                Text(vm.error ?? "No messages")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.items) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.body ?? "")
                        Text([m.direction, m.fromNumber, m.createdAt].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await vm.load() }
    }
}
