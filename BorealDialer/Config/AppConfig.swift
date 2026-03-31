import Foundation

enum AppConfig {
    static let serverBaseURL = URL(string: ProcessInfo.processInfo.environment["SERVER_URL"] ?? "https://server.boreal.financial")!
}
