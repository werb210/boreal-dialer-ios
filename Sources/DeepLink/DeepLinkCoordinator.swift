import Foundation
import Combine

enum DialerDeepLink: Equatable {
    case phone(String, start: Bool)
    case contact(id: String, start: Bool)
}

enum DialerDeepLinkParser {
    static func parse(_ url: URL) -> DialerDeepLink? {
        guard
            url.scheme?.lowercased() == "borealdialer",
            url.host?.lowercased() == "call",
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let queryItems = components.queryItems,
            !queryItems.isEmpty
        else {
            return nil
        }

        let allowedNames: Set<String> = [
            "phone",
            "contactId",
            "start"
        ]

        guard queryItems.allSatisfy({
            allowedNames.contains($0.name)
        }) else {
            return nil
        }

        let uniqueNames = Set(queryItems.map { $0.name })

        guard uniqueNames.count == queryItems.count else {
            return nil
        }

        let values: [String: String] = Dictionary(
            uniqueKeysWithValues: queryItems.map {
                ($0.name, $0.value ?? "")
            }
        )

        let start: Bool

        switch values["start"] {
        case nil, "false":
            start = false

        case "true":
            start = true

        default:
            return nil
        }

        if
            let rawPhone = values["phone"],
            values["contactId"] == nil,
            let phone = normalizedPhone(rawPhone)
        {
            return .phone(
                phone,
                start: start
            )
        }

        if
            let contactId = values["contactId"],
            values["phone"] == nil,
            !contactId.isEmpty,
            contactId.count <= 128,
            contactId.range(
                of: #"^[A-Za-z0-9_-]+$"#,
                options: String.CompareOptions.regularExpression
            ) != nil
        {
            return .contact(
                id: contactId,
                start: start
            )
        }

        return nil
    }

    private static func normalizedPhone(
        _ raw: String
    ) -> String? {
        let trimmed = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard trimmed.first == "+" else {
            return nil
        }

        guard trimmed.count <= 16 else {
            return nil
        }

        let digits = trimmed.dropFirst()

        guard digits.count >= 7 else {
            return nil
        }

        guard digits.allSatisfy({ $0.isNumber }) else {
            return nil
        }

        return trimmed
    }
}

@MainActor
final class DeepLinkCoordinator: ObservableObject {
    static let shared = DeepLinkCoordinator()

    @Published
    private(set) var pending: DialerDeepLink?

    private init() {}

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let link = DialerDeepLinkParser.parse(url) else {
            return false
        }

        guard case .idle = VoiceEngine.shared.state else {
            return false
        }

        // Preserve the deep link while authentication/bootstrap completes.
        pending = link
        return true
    }

    func consumeWhenAuthenticated() -> DialerDeepLink? {
        guard AuthService.shared.isAuthenticated else {
            return nil
        }

        defer {
            pending = nil
        }

        return pending
    }
}
