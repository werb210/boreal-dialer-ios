import SwiftUI

// BOREAL_DIALER_BLOCK_v506_TEAM_LINK_PREVIEWS
// Same card as the portal (BF-portal v505): the first link in a Team message
// shows site, title, description and image, fetched by BF-Server v504
// (GET /team/link-preview), which reads the page server-side.
struct TeamLinkPreviewData: Decodable, Equatable {
    let url: String
    let ok: Bool
    let title: String?
    let description: String?
    let imageUrl: String?
    let siteName: String?
}

enum TeamLinkPreviews {
    static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url
            }
        }
        return nil
    }
}

@MainActor
final class TeamLinkPreviewCache {
    static let shared = TeamLinkPreviewCache()
    private var done: [String: TeamLinkPreviewData?] = [:]

    func preview(for url: URL) async -> TeamLinkPreviewData? {
        let key = url.absoluteString
        if let hit = done[key] { return hit }
        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        struct Resp: Decodable { let preview: TeamLinkPreviewData? }
        var result: TeamLinkPreviewData? = nil
        if let request = try? APIClient.shared.makeRequest(path: "/team/link-preview?url=\(encoded)"),
           let data = try? await APIClient.shared.makeAuthorizedRequest(request),
           let decoded = try? JSONDecoder().decode(Resp.self, from: data),
           let preview = decoded.preview, preview.ok {
            result = preview
        }
        done[key] = result
        return result
    }
}

struct TeamLinkPreviewCard: View {
    let text: String
    @State private var data: TeamLinkPreviewData?

    var body: some View {
        Group {
            if let data, let url = URL(string: data.url) {
                Link(destination: url) {
                    HStack(alignment: .top, spacing: 10) {
                        if let image = data.imageUrl, let imageURL = URL(string: image) {
                            AsyncImage(url: imageURL) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    Color(.systemGray5)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if let site = data.siteName { Text(site).font(.caption2).foregroundColor(.secondary) }
                            if let title = data.title { Text(title).font(.footnote).fontWeight(.semibold).foregroundColor(.primary).lineLimit(2) }
                            if let description = data.description { Text(description).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: 300, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                }
            }
        }
        .task(id: text) {
            guard let url = TeamLinkPreviews.firstLink(in: text) else { data = nil; return }
            data = await TeamLinkPreviewCache.shared.preview(for: url)
        }
    }
}
