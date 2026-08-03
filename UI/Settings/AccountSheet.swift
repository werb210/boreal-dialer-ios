// BOREAL_DIALER_ACCOUNT_SHEET_v42
// There was no way to sign out. AuthService.logout() and AuthManager.signOut()
// both exist and nothing called either - a staff member handing the phone over,
// or signed in as the wrong person, had no route out short of deleting the app.
//
// NotificationsView had the same problem: it lost its tab slot to Calendar in
// v26 and became unreachable. It lives here now.
import SwiftUI

struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lineManager = LineManager.shared

    @State private var confirmingSignOut = false

    // Read from the JWT rather than another round trip - the same claims the
    // Team store already reads for `myId`.
    private var claims: (name: String?, phone: String?) {
        guard let token = TokenStorage.shared.getToken() else { return (nil, nil) }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return (nil, nil) }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, nil) }
        let first = obj["first_name"] as? String
        let last = obj["last_name"] as? String
        let joined = [first, last].compactMap { $0 }.joined(separator: " ")
        return (joined.isEmpty ? obj["email"] as? String : joined, obj["phone"] as? String)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 13) {
                        AvatarCircle(name: claims.name ?? "Staff", size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(claims.name ?? "Signed in").rowTitle()
                            if let phone = claims.phone {
                                Text(PhoneFormat.display(phone)).rowSubtitle()
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    SectionLabel(text: "Account")
                }

                Section {
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    SectionLabel(text: "Activity")
                }

                Section {
                    // Calling, SMS, messages, team and calendar are BF. Only the
                    // Contacts tab reads across silos, and it has its own picker,
                    // so this is stated rather than offered as a choice.
                    HStack {
                        Text("Calling line").rowSubtitle()
                        Spacer()
                        Text(lineManager.activeLine.name)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    SectionLabel(text: "Line")
                }

                Section {
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Sign out of Boreal Dialer?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        // Tell colleagues before dropping the token, or the
                        // roster shows this person available for five minutes.
                        await PresenceHeartbeat.shared.goOffline()
                        AuthService.shared.logout()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need your phone number and a code to sign back in. Any call in progress will end.")
            }
        }
    }
}
