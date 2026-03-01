import Foundation

@MainActor
final class WebSocketManager: ObservableObject {

    static let shared = WebSocketManager()

    private var task: URLSessionWebSocketTask?
    private var session: URLSession
    private var activeLine: Line?
    private var activeAccessToken: String?
    private var reconnectAttempts = 0

    @Published var isConnected = false

    private init() {
        session = URLSession(configuration: .default)
    }

    func connect(line: Line, accessToken: String) {
        disconnect()

        guard let wsURL = line.wsURL else { return }

        activeLine = line
        activeAccessToken = accessToken

        var request = URLRequest(url: wsURL)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        task = session.webSocketTask(with: request)
        task?.resume()

        isConnected = true
        reconnectAttempts = 0
        listen()

        Task {
            try? await API.reconcileActiveCalls()
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .failure:
                    self.isConnected = false
                    self.handleDisconnect()
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.listen()
                }
            }
        }
    }

    private func handleDisconnect() {
        guard reconnectAttempts < 5 else { return }

        reconnectAttempts += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(reconnectAttempts * 2)) {
            guard let line = self.activeLine,
                  let accessToken = self.activeAccessToken else { return }
            self.connect(line: line, accessToken: accessToken)
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let event = try? decoder.decode(SocketEvent.self, from: data) else {
            return
        }

        EventRouter.shared.route(event)
    }
}
