import SwiftUI

// BOREAL_DIALER_OFFLINE_v303 - shows no-signal state and what is waiting to send.
struct OfflineStatusBar: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = OfflineQueue.shared

    static func text(connected: Bool, pending: Int) -> String? {
        if !connected {
            if pending == 0 { return "No signal. Showing saved information." }
            return pending == 1 ? "No signal. 1 change will send when you're back online." : "No signal. \(pending) changes will send when you're back online."
        }
        if pending > 0 { return pending == 1 ? "Sending 1 saved change..." : "Sending \(pending) saved changes..." }
        return nil
    }

    var body: some View {
        if let message = OfflineStatusBar.text(connected: network.isConnected, pending: queue.pendingCount) {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(network.isConnected ? Theme.green : Color.orange)
        }
    }
}
