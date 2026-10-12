// BOREAL_DIALER_URL_TICKET_v790
// BF-Server v789 no longer accepts the full sign-in token in a URL query
// string (it leaks into proxy logs). A WebSocket cannot send an Authorization
// header, so the team socket asks POST /api/auth/url-ticket for a 60-second
// ticket and puts that in ?token= instead. If the server does not offer
// tickets yet (older build), the old behaviour is kept so nothing breaks
// during a rollout.
import Foundation

enum URLTicket {
    private struct Response: Decodable { let ticket: String }

    /// A fresh single-purpose ticket, or nil if the server could not issue one.
    static func fetch() async -> String? {
        guard TokenStorage.shared.getToken() != nil,
              let request = try? APIClient.shared.makeRequest(path: "/auth/url-ticket", method: "POST", body: Data("{}".utf8))
        else { return nil }
        let authorized = APIClient.shared.authorizedRequest(request)
        guard let data = try? await APIClient.shared.execute(authorized),
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              !decoded.ticket.isEmpty
        else { return nil }
        return decoded.ticket
    }

    /// The team socket URL carrying `token` as its query credential.
    static func teamSocketURL(token: String) -> URL? {
        guard let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: APIConfig.TEAM_WS_URL + "?token=\(encoded)")
    }
}
