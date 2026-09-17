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
    @ObservedObject private var callDirectory = CallDirectoryManager.shared

    @State private var confirmingSignOut = false
    @State private var watchEnrollment: WatchEnrollment?
    @State private var watchEnrollmentError: String?
    @State private var generatingWatchCode = false
    @State private var watchLinkSent = false // BOREAL_DIALER_WATCH_AUTOLINK_v1
    @State private var watchStatus = "" // BOREAL_DIALER_WATCH_LINK_TRUTH_v340

    private struct WatchEnrollment: Decodable {
        let oneTimeCode: String
        let expiresAt: Date
    }

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
                    if callDirectory.enabledStatus == .enabled {
                        Label("Caller ID enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                    } else {
                        Button { callDirectory.openSettings() } label: {
                            Label("Open Settings", systemImage: "gear")
                        }
                        Text("Enable Boreal Caller ID in Settings > Phone > Call Blocking & Identification.")
                            .rowSubtitle()
                    }
                } header: {
                    SectionLabel(text: "Incoming caller ID")
                }
                .onAppear { callDirectory.updateEnabledStatus() }

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

                // BOREAL_DIALER_WATCH_LINK_TRUTH_v340
                // This claimed "links automatically" the moment a code was
                // minted, because it threw away the Bool sendEnrollment returns.
                // When the transfer went nowhere the phone still said it had
                // worked, and the Watch's own fallback - "Enter code manually" -
                // was useless because the code was never shown anywhere. Show
                // the code always, and say what actually happened to it.
                Section {
                    Button(generatingWatchCode ? "Linking…" : (watchEnrollment == nil ? "Link Apple Watch" : "Get a new code"))
                        { generateWatchEnrollment() }
                        .disabled(generatingWatchCode)
                    if let watchEnrollment {
                        Text(watchStatus).rowSubtitle()
                        Text(watchEnrollment.oneTimeCode)
                            .font(.system(.title2, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel(Text(watchEnrollment.oneTimeCode.map { String($0) }.joined(separator: " ")))
                        Text("On the Watch: Account → Enter code manually. The code expires \(watchEnrollment.expiresAt, style: .relative) from now.")
                            .rowSubtitle()
                    }
                    if let watchEnrollmentError { Text(watchEnrollmentError).foregroundStyle(.red).font(.caption) }
                } header: { SectionLabel(text: "Apple Watch") }
                .onAppear { if watchEnrollment == nil { generateWatchEnrollment() } }

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
                        await AuthService.shared.logout()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need your phone number and a code to sign back in. Any call in progress will end.")
            }
        }
    }

    private func generateWatchEnrollment() {
        generatingWatchCode = true; watchEnrollmentError = nil; watchEnrollment = nil
        Task { do {
            let request = try APIClient.shared.authorizedRequest(endpoint: "/watch/auth/enrollment", method: "POST")
            let data = try await APIClient.shared.execute(request)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let enrollment = try decoder.decode(WatchEnrollment.self, from: data)
            // BOREAL_DIALER_WATCH_LINK_TRUTH_v340 - the Bool is the whole point.
            await MainActor.run {
                let delivered = WatchBridge.shared.sendEnrollment(enrollment.oneTimeCode)
                watchLinkSent = delivered
                watchStatus = delivered ? "Sent to your Apple Watch. Open Boreal on the Watch." : WatchBridge.shared.linkDiagnostics()
                watchEnrollment = enrollment
                generatingWatchCode = false
            }
        } catch { await MainActor.run { watchEnrollmentError = "Could not generate a Watch code."; generatingWatchCode = false } }
        }
    }
}
