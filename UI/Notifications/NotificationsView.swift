import SwiftUI

struct AppNotification: Identifiable, Decodable {
    let id: String
    let body: String?
    let type: String?
    let contextUrl: String?
    let isRead: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body, type
        case contextUrl = "context_url"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var items: [AppNotification] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do {
            let req = try APIClient.shared.makeRequest(path: "/notifications")
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            struct Resp: Decodable { let items: [AppNotification] }
            items = try JSONDecoder().decode(Resp.self, from: data).items
        } catch {
            self.error = "Could not load notifications."
        }
        loading = false
    }

    func delete(_ id: String) async {
        do {
            let req = try APIClient.shared.makeRequest(path: "/notifications/\(id)", method: "DELETE")
            _ = try await APIClient.shared.makeAuthorizedRequest(req)
            items.removeAll { $0.id == id }
        } catch {
            self.error = "Delete failed."
        }
    }

    func deleteAll() async {
        do {
            let req = try APIClient.shared.makeRequest(path: "/notifications", method: "DELETE")
            _ = try await APIClient.shared.makeAuthorizedRequest(req)
            items.removeAll()
        } catch {
            self.error = "Delete all failed."
        }
    }
}

struct NotificationsView: View {
    @StateObject private var vm = NotificationsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifications").font(.headline)
                Spacer()
                if !vm.items.isEmpty {
                    Button(role: .destructive) {
                        Task { await vm.deleteAll() }
                    } label: {
                        Text("Delete all")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()

            if vm.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.items.isEmpty {
                Text(vm.error ?? "No notifications")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.items) { n in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.body ?? n.type ?? "Notification")
                            if let ts = n.createdAt {
                                Text(ts).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        let ids = idx.map { vm.items[$0].id }
                        Task { for id in ids { await vm.delete(id) } }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await vm.load() }
    }
}
