// BOREAL_DIALER_URL_TICKET_v790
// Shows an image from a staff-only BF-Server media route. AsyncImage cannot
// send an Authorization header, which is why the token used to ride the URL;
// this view fetches the bytes with the header instead.
import SwiftUI
import UIKit

struct AuthorizedMediaImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 220)
            } else if failed {
                Label("Attachment unavailable", systemImage: "photo")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ProgressView().frame(width: 120, height: 90)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard TokenStorage.shared.getToken() != nil else { failed = true; return }
        var request = URLRequest(url: url)
        request.setValue(APIConfig.siloHeader(for: APIConfig.activeSilo), forHTTPHeaderField: "X-Silo")
        request = APIClient.shared.authorizedRequest(request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            image = decoded
        } catch {
            failed = true
        }
    }
}
