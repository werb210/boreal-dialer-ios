import Foundation
import CryptoKit

// BOREAL_DIALER_OFFLINE_v303
// The last good copy of each screen's data (recents, contacts, messages,
// calendar, team), shown when there is no signal instead of an error. Kept in
// the app's private Caches folder, keyed by URL and silo, and wiped on sign-out.
enum ResponseCache {
    static let maxAge: TimeInterval = 7 * 24 * 3600

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("BorealResponseCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func key(for request: URLRequest) -> String? {
        guard let url = request.url?.absoluteString else { return nil }
        let silo = request.value(forHTTPHeaderField: "X-Silo") ?? ""
        let digest = SHA256.hash(data: Data((silo + "|" + url).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isCacheable(_ request: URLRequest) -> Bool {
        (request.httpMethod ?? "GET").uppercased() == "GET"
    }

    static func store(_ data: Data, for request: URLRequest) {
        guard isCacheable(request), let dir = directory, let key = key(for: request) else { return }
        try? data.write(to: dir.appendingPathComponent(key), options: .atomic)
    }

    static func load(for request: URLRequest) -> Data? {
        guard isCacheable(request), let dir = directory, let key = key(for: request) else { return nil }
        let file = dir.appendingPathComponent(key)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge else { return nil }
        return try? Data(contentsOf: file)
    }

    static func clear() {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: base.appendingPathComponent("BorealResponseCache", isDirectory: true))
    }
}
