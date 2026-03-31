import Foundation

enum AppConfig {
    static let serverBaseURL: URL = {
        guard
            let rawValue = ProcessInfo.processInfo.environment["SERVER_URL"],
            !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let url = URL(string: rawValue)
        else {
            fatalError("Missing required SERVER_URL environment variable")
        }

        return url
    }()
}
