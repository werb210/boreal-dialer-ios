import SwiftUI

struct AppNotification: Identifiable, Decodable {
    let id: String
    let body: String?
    let type: String?
    let contextUrl: String?
    var isRead: Bool?
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

    // BOREAL_DIALER_NOTIFICATIONS_READ_v789 - POST /api/notifications/:id/read
    func markRead(_ id: String) async {
        do {
            let req = try APIClient.shared.makeRequest(path: "/notifications/\(Self.pathSegment(id))/read", method: "POST")
            _ = try await APIClient.shared.makeAuthorizedRequest(req)
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].isRead = true }
        } catch {
            self.error = "Mark read failed."
        }
    }

    // BOREAL_DIALER_NOTIFICATIONS_READ_v789 - POST /api/notifications/read-all
    func markAllRead() async {
        do {
            let req = try APIClient.shared.makeRequest(path: "/notifications/read-all", method: "POST")
            _ = try await APIClient.shared.makeAuthorizedRequest(req)
            for index in items.indices { items[index].isRead = true }
        } catch {
            self.error = "Mark all read failed."
        }
    }

    var hasUnread: Bool { items.contains { !($0.isRead ?? false) } }

    nonisolated static func pathSegment(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
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
                if vm.hasUnread {
                    Button("Mark all read") { Task { await vm.markAllRead() } }
                        .padding(.trailing, 8)
                }
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
                                .fontWeight((n.isRead ?? false) ? .regular : .semibold)
                            if let ts = n.createdAt {
                                Text(ts).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        // BOREAL_DIALER_NOTIFICATIONS_READ_v789
                        .swipeActions(edge: .leading) {
                            if !(n.isRead ?? false) {
                                Button("Mark read") { Task { await vm.markRead(n.id) } }
                                    .tint(.blue)
                            }
                        }
                        // Custom swipe actions replace the synthesized onDelete swipe.
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { Task { await vm.delete(n.id) } }
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
