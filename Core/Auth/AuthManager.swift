import Combine
import Foundation

final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isSignedIn: Bool = false
    @Published var username: String = ""

    private init() {}

    func signIn(username: String, password: String) {
        // Mock login.
        _ = password
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.username = username
            self.isSignedIn = true
        }
    }

    func signOut() {
        isSignedIn = false
        username = ""
    }
}
