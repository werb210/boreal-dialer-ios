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
        case .bridging: "Bridging…"
        case .ringing: "Ringing…"
        case .connected: "Connected"
        case .ended: "Call ended"
        default: status.rawValue.capitalized
        }
    }
    private func start() {
        guard let destination = PhoneNumberNormalizer.normalize(number) else { errorMessage = "Enter a valid number"; return }
        let captured = CallRequest(destination: destination, line: line)
        status = .requesting; errorMessage = nil
        Task { do { status = try await transport.startCall(captured) }
            catch let error as WatchServiceError { status = .failed; errorMessage = error.safeMessage }
            catch { status = .failed; errorMessage = "Call request failed" }
        }
    }
}

struct WatchContactsView: View {
    @State private var query = ""; @State private var results: [ContactSummary] = []; @State private var message: String?
    @State private var line: BorealLine = .BF
    private let service: any WatchDirectoryService = DirectWatchDirectoryService()
    var body: some View {
        List {
            TextField("Search CRM", text: $query)
            Picker("Line", selection: $line) { ForEach(BorealLine.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Button("Search") { search() }.disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
            if let message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            ForEach(results) { contact in
                NavigationLink(destination: ContactDetailView(contact: contact)) {
                    VStack(alignment: .leading) { Text(contact.name); if let company = contact.company { Text(company).font(.caption2) } }
                }
            }
        }.navigationTitle("Contacts")
    }
    private func search() { Task { do { results = try await service.search(query, line: line, limit: 10) }
        catch { message = "Search unavailable" } } }
}

struct ContactDetailView: View {
    let contact: ContactSummary
    var body: some View { List { Text(contact.name); if let company = contact.company { Text(company) }; Text(contact.primaryPhone); NavigationLink("Dial", destination: PrefilledDialView(number: contact.primaryPhone)) } }
}
struct PrefilledDialView: View { let number: String; var body: some View { WatchDialView(initialNumber: number) } }

struct WatchRecentsView: View {
    @State private var recents: [WatchRecentCall] = []; @State private var unavailable = false
    @State private var line: BorealLine = .BF
    private let service: any WatchRecentsService = DirectWatchRecentsService()
    var body: some View { List { Picker("Line", selection: $line) { ForEach(BorealLine.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; if unavailable { Text("Recents unavailable").font(.caption) }; ForEach(recents) { Text($0.name ?? $0.number) } }.navigationTitle("Recents").task(id: line) { do { unavailable = false; recents = try await service.fetch(line: line, limit: 25) } catch { unavailable = true } } }
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
    @State private var code = ""; @State private var linked = false; @State private var fallback = false
    @State private var message: String?
    var body: some View { List {
        if linked {
            Text("Linked")
            Toggle("Standalone cellular fallback", isOn: $fallback).onChange(of: fallback) { enabled in updateRouting(enabled) }
            Button("Sign Out", role: .destructive) { Task { do { try await WatchAuthService.shared.logout(client: WatchAPIClient()); await MainActor.run { store.clearSensitiveData(); linked = false; message = "Signed out on this Watch" } } catch { await MainActor.run { message = "Could not revoke this Watch. Try again." } } } }
        } else {
            Text("Link this Apple Watch").font(.headline)
            TextField("8-digit code", text: $code)
            Button("Link") { Task { do { try await WatchAuthService.shared.link(oneTimeCode: code); await MainActor.run { code = ""; linked = true; message = nil } } catch let error as WatchServiceError { await MainActor.run { message = error.safeMessage } } catch { await MainActor.run { message = "Unable to link Watch" } } } }.disabled(code.count != 8)
        }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }.navigationTitle("Account").task { linked = await WatchAuthService.shared.restore(); if linked { try? await WatchAPIClient().registerDevice() } } }
    private func updateRouting(_ enabled: Bool) { Task { do {
        guard let session = await WatchAuthService.shared.session else { return }
        struct Body: Encodable { let enabled: Bool }
        _ = try await WatchAPIClient().request(path: "/watch/devices/\(session.deviceId)/standalone-routing", method: "PUT", body: JSONEncoder().encode(Body(enabled: enabled)))
    } catch let error as WatchServiceError { await MainActor.run { fallback = false; message = error.safeMessage } } catch { await MainActor.run { fallback = false; message = "Unable to update fallback" } } } }
}
