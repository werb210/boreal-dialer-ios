import Foundation

// BOREAL_DIALER_BACKGROUND_SEND_v309
// Call outcomes, tasks and call logs saved with no signal (v303) used to wait
// until the dialer was opened again. When the app goes to the background they
// are now handed to a background URLSession: iOS sends them after the app is
// closed and retries when signal returns. The HTTP status is recorded for the
// queue to read back the next time the app opens.
final class BackgroundSender: NSObject, URLSessionTaskDelegate {
    static let shared = BackgroundSender()
    static let sessionIdentifier = "com.boreal.dialer.background-send"
    var systemCompletion: (() -> Void)?

    private let resultsKey = "boreal.dialer.backgroundSend.results"
    private let lock = NSLock()

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: BackgroundSender.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("BackgroundSend", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func enqueue(id: String, request: URLRequest, body: Data) throws {
        let bodyFile = directory.appendingPathComponent("\(id).body")
        try body.write(to: bodyFile, options: .atomic)
        let task = session.uploadTask(with: request, fromFile: bodyFile)
        task.taskDescription = id
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        let status = error == nil ? ((task.response as? HTTPURLResponse)?.statusCode ?? 0) : 0
        lock.lock()
        var all = UserDefaults.standard.dictionary(forKey: resultsKey) ?? [:]
        all[id] = status
        UserDefaults.standard.set(all, forKey: resultsKey)
        lock.unlock()
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).body"))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.systemCompletion?()
            self.systemCompletion = nil
        }
    }

    func results() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        let all = UserDefaults.standard.dictionary(forKey: resultsKey) ?? [:]
        return all.compactMapValues { $0 as? Int }
    }

    func acknowledge(_ ids: [String]) {
        lock.lock(); defer { lock.unlock() }
        var all = UserDefaults.standard.dictionary(forKey: resultsKey) ?? [:]
        for id in ids { all.removeValue(forKey: id) }
        UserDefaults.standard.set(all, forKey: resultsKey)
    }

    func cancelAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        try? FileManager.default.removeItem(at: directory)
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: resultsKey)
    }

    enum Outcome: Equatable { case sent, refused, retry }

    /// sent: on the server. refused: rejected for good. retry: back to the in-app queue.
    static func outcome(for status: Int) -> Outcome {
        if (200..<300).contains(status) { return .sent }
        if status == 0 || status == 401 || status == 408 || status == 429 || status >= 500 { return .retry }
        return .refused
    }
}
