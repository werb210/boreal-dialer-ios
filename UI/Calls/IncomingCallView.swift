import SwiftUI
import TwilioVoice

// BOREAL_DIALER_UI_COMPILES_v6 - takes the invite, not a connected Call.
struct IncomingCallView: View {
    let invite: CallInvite
    @State private var contactName: String = "Unknown Caller"
    @State private var company: String = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Caller info
            VStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
                Text(contactName)
                    .font(.largeTitle)
                    .bold()
                if !company.isEmpty {
                    Text(company)
                        .foregroundColor(.secondary)
                }
                Text("Incoming Call")
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Accept / Decline
            HStack(spacing: 60) {
                Button {
                    VoiceManager.shared.rejectCall(invite: invite)
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .padding(24)
                        .background(Color.red)
                        .clipShape(Circle())
                }

                Button {
                    VoiceManager.shared.acceptCall(invite: invite)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .padding(24)
                        .background(Color.green)
                        .clipShape(Circle())
                }
            }

            Spacer()
        }
        .onAppear { lookupCaller() }
    }

    private func lookupCaller() {
        let from = invite.from ?? ""
        guard !from.isEmpty,
              let encodedPhone = from.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(APIConfig.baseURL)/crm/contacts?phone=\(encodedPhone)") else { return }

        Task {
            var request = URLRequest(url: url)
            if let token = TokenStorage.shared.getToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            if let (data, _) = try? await URLSession.shared.data(for: request),
               let contacts = try? JSONDecoder().decode([[String: String]].self, from: data),
               let contact = contacts.first {
                await MainActor.run {
                    contactName = contact["name"] ?? contactName
                    company = contact["company"] ?? ""
                }
            }
        }
    }
}
