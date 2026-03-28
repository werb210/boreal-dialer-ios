import Foundation
import Combine

final class CallDurationManager: ObservableObject {

    static let shared = CallDurationManager()

    @Published private(set) var formattedDuration: String = "00:00"

    private let callStartStorageKey = "voice.call.startDate"
    private var callStartDate: Date?
    private var timer: Timer?

    private init() {
        callStartDate = UserDefaults.standard.object(forKey: callStartStorageKey) as? Date
        updateDuration()
    }

    func start() {
        callStartDate = Date()
        UserDefaults.standard.set(callStartDate, forKey: callStartStorageKey)
        updateDuration()
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        callStartDate = nil
        UserDefaults.standard.removeObject(forKey: callStartStorageKey)
        formattedDuration = "00:00"
    }

    func resumeIfNeeded() {
        if callStartDate == nil {
            callStartDate = UserDefaults.standard.object(forKey: callStartStorageKey) as? Date
        }

        guard callStartDate != nil else { return }

        updateDuration()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0,
                                     repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
    }

    private func updateDuration() {
        guard let start = callStartDate else {
            formattedDuration = "00:00"
            return
        }

        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60

        formattedDuration = String(format: "%02d:%02d",
                                   minutes,
                                   seconds)
    }
}
