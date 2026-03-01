import CryptoKit
import Foundation

final class SecureMessageStore {

    static let shared = SecureMessageStore()

    private let keyTag = "boreal.secure.message.key"
    private let key: SymmetricKey

    private init() {
        if let keyData = KeychainService.shared.loadData(keyTag) {
            key = SymmetricKey(data: keyData)
        } else {
            let generated = SymmetricKey(size: .bits256)
            let data = generated.withUnsafeBytes { Data($0) }
            KeychainService.shared.saveData(data, for: keyTag)
            key = generated
        }
    }

    func encrypt(_ text: String) throws -> Data {
        let data = Data(text.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw NSError(domain: "SecureMessageStore", code: -1)
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> String {
        let box = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(box, using: key)
        return String(decoding: decrypted, as: UTF8.self)
    }
}
