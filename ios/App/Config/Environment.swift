import Foundation

enum Environment {
    static let serverURL: String = {
        let value = ProcessInfo.processInfo.environment["SERVER_URL"] ?? "https://YOUR_SERVER_URL"
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static let authToken: String = {
        let value = ProcessInfo.processInfo.environment["AUTH_TOKEN"] ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()
}
