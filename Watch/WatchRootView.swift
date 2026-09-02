import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchEventStore
    var body: some View {
        NavigationStack {
            List {
                if let call = store.companionCall { CompanionCallView(call: call) }
                NavigationLink("Dial", destination: WatchDialView())
                NavigationLink("Contacts", destination: WatchContactsView())
                NavigationLink("Recent Calls", destination: WatchRecentsView())
                NavigationLink("Notifications", destination: WatchNotificationsView())
                NavigationLink("Account", destination: WatchAccountView())
            }.navigationTitle("Boreal")
        }.onAppear { store.startCompanionOptimization() }
    }
}

struct WatchDialView: View {
    @State private var number: String
    @State private var line: BorealLine = .BF
    @State private var status: WatchCallStatus = .idle
    @State private var errorMessage: String?
    private let transport: any WatchCallTransport = ServerBridgeWatchCallTransport()
    init(initialNumber: String = "") { _number = State(initialValue: initialNumber) }
    var body: some View {
        Form {
            TextField("Phone number", text: $number)
            Picker("Line", selection: $line) { ForEach(BorealLine.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Button { start() } label: { Label("Call", systemImage: "phone.fill") }
                .disabled(status == .requesting)
            if status != .idle { Text(statusText).font(.caption).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.caption2).foregroundStyle(.red) }
        }.navigationTitle("Dial")
    }
    private var statusText: String {
        switch status {
        case .requesting: "Requesting callback…"
        case .waitingForCallback: "Waiting for carrier call…"
        default: status.rawValue
        }
    }
    private func start() {
        guard let destination = PhoneNumberNormalizer.normalize(number) else { errorMessage = "Enter a valid number"; return }
        let captured = CallRequest(destination: destination, line: line)
        status = .requesting; errorMessage = nil
        Task { do { status = try await transport.startCall(captured) }
            catch WatchServiceError.serverCapabilityUnavailable { status = .failed; errorMessage = "Standalone calling awaits server support" }
            catch { status = .failed; errorMessage = "Call request failed" }
        }
    }
}

struct WatchContactsView: View {
    @State private var query = ""; @State private var results: [ContactSummary] = []; @State private var message: String?
    private let service: any WatchDirectoryService = DirectWatchDirectoryService()
    var body: some View {
        List {
            TextField("Search CRM", text: $query)
            Button("Search") { search() }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            if let message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            ForEach(results) { contact in
                NavigationLink(destination: ContactDetailView(contact: contact)) {
                    VStack(alignment: .leading) { Text(contact.name); if let company = contact.company { Text(company).font(.caption2) } }
                }
            }
        }.navigationTitle("Contacts")
    }
    private func search() { Task { do { results = try await service.search(query, limit: 10) }
        catch WatchServiceError.serverCapabilityUnavailable { message = "Contact search awaits a confirmed server contract" }
        catch { message = "Search unavailable" } } }
}

struct ContactDetailView: View {
    let contact: ContactSummary
    var body: some View { List { Text(contact.name); if let company = contact.company { Text(company) }; Text(contact.primaryPhone); NavigationLink("Dial", destination: PrefilledDialView(number: contact.primaryPhone)) } }
}
struct PrefilledDialView: View { let number: String; var body: some View { WatchDialView(initialNumber: number) } }

struct WatchRecentsView: View {
    @State private var recents: [RecentCall] = []; @State private var unavailable = false
    private let service: any WatchRecentsService = DirectWatchRecentsService()
    var body: some View { List { if unavailable { Text("Recents await server support").font(.caption) }; ForEach(recents) { Text($0.name ?? $0.number) } }.navigationTitle("Recents").task { do { recents = try await service.fetch(limit: 25) } catch { unavailable = true } } }
}

struct WatchNotificationsView: View {
    @EnvironmentObject private var store: WatchEventStore
    var body: some View { List(store.events, id: \.callId) { event in VStack(alignment: .leading) { Text(event.subtitle); Text(event.title).font(.caption2).foregroundStyle(.secondary) } }.navigationTitle("Notifications") }
}

struct CompanionCallView: View {
    let call: WatchEvent
    @EnvironmentObject private var store: WatchEventStore
    var body: some View { Section("iPhone call") { Text(call.subtitle); HStack { Button { store.sendCompanionAction(.decline) } label: { Image(systemName: "phone.down.fill") }.tint(.red); Button { store.sendCompanionAction(.answer) } label: { Image(systemName: "phone.fill") }.tint(.green) }; Text("Controlled by nearby iPhone").font(.caption2).foregroundStyle(.secondary) } }
}

struct WatchAccountView: View {
    @EnvironmentObject private var store: WatchEventStore
    @State private var message = "Authentication can be restored independently. Standalone enrollment requires the documented server link flow."
    var body: some View { List { Text(message).font(.caption); Button("Sign Out", role: .destructive) { Task { await WatchAuthService.shared.logout(); await MainActor.run { store.clearSensitiveData(); message = "Signed out on this Watch" } } } }.navigationTitle("Account") }
}
