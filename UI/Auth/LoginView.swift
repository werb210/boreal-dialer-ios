import SwiftUI

struct LoginView: View {

    @State private var phone = ""
    @State private var otp = ""
    @ObservedObject var auth = AuthService.shared

    var body: some View {

        VStack(spacing: 20) {

            TextField("Phone", text: $phone)
                .textFieldStyle(.roundedBorder)

            TextField("OTP Code", text: $otp)
                .textFieldStyle(.roundedBorder)

            Button("Login") {
                Task {
                    try? await auth.login(phone: phone, otp: otp)
                }
            }
        }
        .padding()
    }
}
