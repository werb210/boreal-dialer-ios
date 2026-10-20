import SwiftUI

// BOREAL_DIALER_OFFLINE_v303 - shows no-signal state and what is waiting to send.
// BOREAL_DIALER_v831_DIALER_POLISH - and what the server refused: a saved change that can't go through is listed with
// the reason (Review) instead of disappearing.
struct OfflineStatusBar: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var queue = OfflineQueue.shared
    @State private var reviewing = false

    static func text(connected: Bool, pending: Int) -> String? {
        if !connected {
            if pending == 0 { return "No signal. Showing saved information." }
            return pending == 1 ? "No signal. 1 change will send when you're back online." : "No signal. \(pending) changes will send when you're back online."
        }
        if pending > 0 { return pending == 1 ? "Sending 1 saved change..." : "Sending \(pending) saved changes..." }
        return nil
    }

    nonisolated static func failedText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 saved change couldn't be sent. Tap to review." : "\(count) saved changes couldn't be sent. Tap to review."
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = OfflineStatusBar.text(connected: network.isConnected, pending: queue.pendingCount) {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(network.isConnected ? Theme.green : Color.orange)
            }
            if let failed = OfflineStatusBar.failedText(queue.failedItems.count) {
                Button { reviewing = true } label: {
                    Text(failed)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.70, green: 0.11, blue: 0.11))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the changes that weren't saved")
            }
        }
        .sheet(isPresented: $reviewing) { FailedChangesSheet() }
    }
}

// BOREAL_DIALER_v831_DIALER_POLISH
struct FailedChangesSheet: View {
    @ObservedObject private var queue = OfflineQueue.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if queue.failedItems.isEmpty {
                    Text("Nothing is waiting.").foregroundStyle(.secondary)
                }
                ForEach(queue.failedItems, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.label).font(.headline)
                        Text("Saved \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let failure = item.failure {
                            Text(failure).font(.subheadline)
                        }
                        HStack(spacing: 12) {
                            Button("Try again") { queue.retry(item.id) }
                                .buttonStyle(.borderedProminent)
                            Button("Discard", role: .destructive) { queue.discard(item.id) }
                                .buttonStyle(.bordered)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Not saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
