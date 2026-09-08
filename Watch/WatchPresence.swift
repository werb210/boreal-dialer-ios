// BOREAL_DIALER_BLOCK_v210_WATCH_PHASE2_v1
// Availability from the wrist. Server contract is the existing
// GET/POST /api/telephony/presence that drives the portal's on-call badge —
// the Watch is a second client of it, not a new surface.
import Foundation
import SwiftUI

enum WatchAvailability: String, Codable, CaseIterable, Sendable {
    case available, away, on_call

    var title: String {
        switch self {
        case .available: return "Available"
        case .away: return "Away"
        case .on_call: return "On call"
        }
    }
}

@MainActor
final class WatchPresenceModel: ObservableObject {
    @Published private(set) var status: WatchAvailability = .away
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?

    private let transport: WatchPresenceTransport

    init(transport: WatchPresenceTransport = WatchPresenceHTTPTransport()) {
        self.transport = transport
    }

    func refresh() async {
        busy = true; defer { busy = false }
        do { status = try await transport.fetch(); lastError = nil }
        catch { lastError = "Unavailable" }
    }

    /// on_call is set by the telephony layer, never by the user — offering it as a
    /// manual toggle would let the wrist contradict the actual call state.
    func set(_ next: WatchAvailability) async {
        guard next != .on_call else { return }
        busy = true; defer { busy = false }
        let previous = status
        status = next
        do { try await transport.update(next); lastError = nil }
        catch { status = previous; lastError = "Could not update" }
    }
}

protocol WatchPresenceTransport: Sendable {
    func fetch() async throws -> WatchAvailability
    func update(_ status: WatchAvailability) async throws
}

struct WatchPresenceHTTPTransport: WatchPresenceTransport {
    private var base: String {
        (Bundle.main.object(forInfoDictionaryKey: "BorealAPIBaseURL") as? String)
            ?? "https://server.boreal.financial/api"
    }

    private func request(_ path: String, method: String, body: Data?) async throws -> Data {
        guard let url = URL(string: base + path) else { throw WatchServiceError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("BF", forHTTPHeaderField: "X-Silo")
        guard let token = await WatchAuthService.shared.token else { throw WatchServiceError.notAuthenticated }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WatchServiceError.invalidResponse
        }
        return data
    }

    func fetch() async throws -> WatchAvailability {
        let data = try await request("/telephony/presence", method: "GET", body: nil)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        return WatchAvailability(rawValue: decoded["status"] ?? "") ?? .away
    }

    func update(_ status: WatchAvailability) async throws {
        let body = try JSONEncoder().encode(["status": status.rawValue])
        _ = try await request("/telephony/presence", method: "POST", body: body)
    }
}

struct WatchAvailabilityView: View {
    @StateObject private var model = WatchPresenceModel()

    var body: some View {
        List {
            ForEach(WatchAvailability.allCases.filter { $0 != .on_call }, id: \.self) { option in
                Button {
                    Task { await model.set(option) }
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer()
                        if model.status == option { Image(systemName: "checkmark") }
                    }
                }
                .disabled(model.busy)
            }
            if model.status == .on_call {
                Text("On call").foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Availability")
        .task { await model.refresh() }
    }
}
