import Foundation

enum DialerDeepLink: Equatable {
    case phone(String, start: Bool)
    case contact(id: String, start: Bool)
}

enum DialerDeepLinkParser {
    static func parse(_ url: URL) -> DialerDeepLink? {
        guard url.scheme?.lowercased() == "borealdialer", url.host?.lowercased() == "call",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let allowed = Set(["phone", "contactId", "start"])
        guard components.queryItems.allSatisfy({ allowed.contains($0.name) }),
              Set(components.queryItems.map(\.name)).count == components.queryItems.count else { return nil }
        let values = Dictionary(uniqueKeysWithValues: components.queryItems.map { ($0.name, $0.value ?? "") })
        let start: Bool
        switch values["start"] { case nil, "false": start = false; case "true": start = true; default: return nil }
        if let raw = values["phone"], values["contactId"] == nil,
           let phone = normalizedPhone(raw) { return .phone(phone, start: start) }
        if let id = values["contactId"], values["phone"] == nil,
           !id.isEmpty, id.count <= 128,
           id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            return .contact(id: id, start: start)
        }
        return nil
    }

    private static func normalizedPhone(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "+", trimmed.count <= 16,
              trimmed.dropFirst().count >= 7,
              trimmed.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return trimmed
    }
}

@MainActor
final class DeepLinkCoordinator: ObservableObject {
    static let shared = DeepLinkCoordinator()
    @Published private(set) var pending: DialerDeepLink?
    private init() {}

    @discardableResult func receive(_ url: URL) -> Bool {
        guard let link = DialerDeepLinkParser.parse(url) else { return false }
        guard case .idle = VoiceEngine.shared.state else { return false }
        pending = link // survives asynchronous authentication/bootstrap
        return true
    }

    func consumeWhenAuthenticated() -> DialerDeepLink? {
        guard AuthService.shared.isAuthenticated else { return nil }
        defer { pending = nil }
        return pending
    }
}
