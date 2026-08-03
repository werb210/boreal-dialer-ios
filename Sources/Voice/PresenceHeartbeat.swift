// BOREAL_DIALER_PRESENCE_v41
// The server collapses a staff member to offline five minutes after their last
// heartbeat, so posting presence once at login is not enough - you would go dark
// five minutes in while sitting in the app.
//
//   POST /api/telephony/presence            { status }
//   POST /api/telephony/presence/heartbeat
//
// Heartbeats stop when the app backgrounds. That is deliberate: a phone in a
// pocket is not someone who can take a call, and claiming otherwise sends work
// to a person who will not answer. VoIP push still reaches them.
import Foundation
import UIKit

@MainActor
final class PresenceHeartbeat {

    static let shared = PresenceHeartbeat()

    private var task: Task<Void, Never>?
    // Well inside the server's five-minute window, so one dropped request does
    // not flip a working handset to offline.
    private let interval: UInt64 = 90_000_000_000

    private init() {}

    func start() {
        stop()
        task = Task { [weak self] in
            guard let self else { return }
            await self.publish(status: "available")
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.interval)
                guard !Task.isCancelled else { break }
                await self.beat()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // Signing out or backgrounding says so rather than letting the timeout do
    // it, so colleagues see the change immediately.
    func goOffline() async {
        stop()
        await publish(status: "offline")
    }

    func publish(status: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["status": status])
            let request = try APIClient.shared.makeRequest(
                path: "/telephony/presence", method: "POST", body: body
            )
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
        } catch {
            // Presence is not worth interrupting anyone over.
        }
    }

    private func beat() async {
        do {
            let request = try APIClient.shared.makeRequest(
                path: "/telephony/presence/heartbeat", method: "POST"
            )
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
        } catch {
            // A missed beat is recovered by the next one, inside the window.
        }
    }
}
