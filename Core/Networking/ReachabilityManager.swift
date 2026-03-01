import Foundation
import Network

final class ReachabilityManager: ObservableObject {
    static let shared = ReachabilityManager()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "reachability.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    ConversationsService.shared.retryQueuedMessages()
                }
            }
        }
        monitor.start(queue: queue)
    }
}
