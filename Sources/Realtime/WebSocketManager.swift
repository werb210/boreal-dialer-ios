import Foundation

@MainActor
final class WebSocketManager: ObservableObject {

    static let shared = WebSocketManager()

    private var activeLine: Line?
    private var activeAccessToken: String?

    @Published var isConnected = false

    private init() {}

    func connect(line: Line, accessToken: String) {
        activeLine = line
        activeAccessToken = accessToken
        isConnected = true

        Task {
            do {
                let serverState = try await API.getActiveCalls()
                if serverState.isEmpty {
                    CallManager.shared.forceTerminate()
                } else {
                    CallManager.shared.syncWithServer(serverState)
                }
            } catch {
                try? await API.reconcileActiveCalls()
            }
        }
    }

    func disconnect() {
        activeLine = nil
        activeAccessToken = nil
        isConnected = false
    }
}
