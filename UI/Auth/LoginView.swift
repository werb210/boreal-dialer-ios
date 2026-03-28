import SwiftUI

struct LoginView: View {

    @State private var phone = ""
    @State private var otp = ""
    @State private var otpRequested = false
    @ObservedObject var auth = AuthService.shared

    var body: some View {

        VStack(spacing: 20) {

            TextField("Phone", text: $phone)
                .textFieldStyle(.roundedBorder)

            TextField("OTP Code", text: $otp)
                .textFieldStyle(.roundedBorder)

            Button("Send OTP") {
                Task {
                    otpRequested = await auth.startOTP(phone: phone)
                }
            }

            Button("Login") {
                Task {
                    try? await auth.login(phone: phone, otp: otp)
                }
            }
            .disabled(!otpRequested)
        }
        .padding()
    }
}
