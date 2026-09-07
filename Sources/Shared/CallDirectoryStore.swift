import Foundation

struct CallDirectoryEntry: Codable, Equatable {
    let phoneNumber: Int64
    let label: String
}

enum CallDirectoryStore {
    static let appGroupIdentifier = "group.financial.boreal.dialer"
    private static let fileName = "caller-directory-v1.json"

    static func entries() -> [CallDirectoryEntry] {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CallDirectoryEntry].self, from: data)
        else { return [] }

        return decoded.sorted { $0.phoneNumber < $1.phoneNumber }
    }

    static func save(_ entries: [CallDirectoryEntry]) throws {
        guard let url = fileURL() else { throw StoreError.sharedContainerUnavailable }
        let sorted = entries.sorted { $0.phoneNumber < $1.phoneNumber }
        try JSONEncoder().encode(sorted).write(to: url, options: .atomic)
    }

    /// Converts an E.164 string into CallKit's signed 64-bit representation.
    static func phoneNumber(fromE164 value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "+" else { return nil }
        let digits = trimmed.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let number = Int64(digits), number > 0 else { return nil }
        return number
    }

    private static func fileURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )?.appendingPathComponent(fileName, isDirectory: false)
    }

    enum StoreError: Error {
        case sharedContainerUnavailable
    }
}
