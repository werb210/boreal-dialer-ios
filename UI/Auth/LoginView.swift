import SwiftUI

struct LoginView: View {

    @State private var phone = ""
    @State private var otp = ""
    @State private var otpRequested = false
    // BOREAL_DIALER_UI_COMPILES_v6
    @State private var errorMessage: String?
    @State private var busy = false
    @ObservedObject var auth = AuthService.shared

    var body: some View {

        VStack(spacing: 20) {

            TextField("Phone", text: $phone)
                .textFieldStyle(.roundedBorder)

            TextField("OTP Code", text: $otp)
                .textFieldStyle(.roundedBorder)

            Button("Send OTP") {
                Task {
                    busy = true
                    errorMessage = nil
                    do {
                        otpRequested = try await auth.startOTP(phone: phone)
                        if !otpRequested {
                            errorMessage = "We couldn't send a code to that number."
                        }
                    } catch {
                        errorMessage = "We couldn't send a code. Check the number and try again."
                    }
                    busy = false
                }
            }
            .disabled(busy || phone.isEmpty)

            Button("Login") {
                Task {
                    busy = true
                    errorMessage = nil
                    do {
                        try await auth.login(phone: phone, otp: otp)
                    } catch {
                        errorMessage = "That code didn't work. Please try again."
                    }
                    busy = false
                }
            }
            .disabled(busy || !otpRequested)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
