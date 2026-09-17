import Foundation
#if canImport(AppIntents)
import AppIntents
#endif

// BOREAL_DIALER_SIRI_CALL_CLIENT_v320
// "Hey Siri, call a client with Boreal Dialer" -> "Who do you want to call?" ->
// "Tanya Voss" -> the dialer finds her in the CRM and places the call through
// Boreal (so it is logged, recorded and shows the Boreal caller ID), instead of
// Siri dialing her from the personal phone. New Call, Next Meeting and What's
// Due already existed; this adds calling a client by name.
enum BorealClientLookup {
    /// CRM phones come in many shapes ("(780) 916-7413", "780-916-7413", "+17809167413").
    static func e164(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter { $0.isNumber }
        if raw.trimmingCharacters(in: .whitespaces).hasPrefix("+"), (8...15).contains(digits.count) { return "+" + digits }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    /// Exact name match first, otherwise the first match that has a phone number.
    static func best(_ contacts: [CRMContact], for query: String) -> CRMContact? {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let callable = contacts.filter { e164($0.callablePhone) != nil }
        return callable.first { $0.displayName.lowercased() == wanted }
            ?? callable.first { ($0.companyName ?? "").lowercased() == wanted }
            ?? callable.first
    }

    static func search(_ query: String) async throws -> [CRMContact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let request = try APIClient.shared.makeRequest(path: "/crm/contacts?pageSize=10&q=\(encoded)", silo: .bf)
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try JSONDecoder().decode(ContactsListEnvelope.self, from: data).data
    }

    static func callURL(phone: String) -> URL? {
        var components = URLComponents()
        components.scheme = "borealdialer"
        components.host = "call"
        components.queryItems = [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "start", value: "true")]
        return components.url
    }
}

#if canImport(AppIntents)
@available(iOS 16.0, *)
struct CallBorealClientIntent: AppIntent {
    static var title: LocalizedStringResource = "Call a Boreal Client"
    static var description = IntentDescription("Finds a client in Boreal and calls them from your Boreal line.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Client", requestValueDialog: "Who do you want to call?")
    var client: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard TokenStorage.shared.getToken() != nil else {
            return .result(dialog: "Open Boreal Dialer and sign in first.")
        }
        let matches: [CRMContact]
        do {
            matches = try await BorealClientLookup.search(client)
        } catch {
            return .result(dialog: "I couldn't reach Boreal right now.")
        }
        guard let match = BorealClientLookup.best(matches, for: client),
              let phone = BorealClientLookup.e164(match.callablePhone),
              let url = BorealClientLookup.callURL(phone: phone) else {
            return .result(dialog: "I couldn't find a phone number for \(client) in Boreal.")
        }
        DeepLinkCoordinator.shared.receive(url)
        return .result(dialog: "Calling \(match.displayName).")
    }
}
#endif
