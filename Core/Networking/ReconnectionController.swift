import Foundation
import Network

final class ReconnectionController {

    static let shared = ReconnectionController()

    private let monitor = NWPathMonitor()
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                Task { @MainActor in
                    await VoiceEngine.shared.reconcile()
                    await OfflineQueue.shared.flush()
                }
            }
        }

        monitor.start(queue: DispatchQueue.global(qos: .background))
    }
}
