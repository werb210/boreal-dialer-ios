import SwiftUI

struct LoginView: View {

    @State private var phone = ""
    @State private var otp = ""
    @State private var otpRequested = false
    // BOREAL_DIALER_UI_COMPILES_v6
    @State private var errorMessage: String?
    @State private var busy = false
    @ObservedObject var auth = AuthService.shared
    // BOREAL_DIALER_KEYPAD_ICON_PLIST_v22
    private enum Field { case phone, code }
    @FocusState private var focused: Field?

    var body: some View {

        VStack(spacing: 20) {

            TextField("Phone", text: $phone)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focused, equals: .phone)

            TextField("OTP Code", text: $otp)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                // Lets iOS offer the code straight from the SMS.
                .textContentType(.oneTimeCode)
                .focused($focused, equals: .code)

            Button("Send OTP") {
                Task {
                    busy = true
                    errorMessage = nil
                    do {
                        otpRequested = try await auth.startOTP(phone: phone)
                        if otpRequested { focused = .code }
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
        .onAppear { focused = .phone }
        // Six digits is the whole code - no reason to make anyone tap Login.
        .onChange(of: otp) { value in
            if value.count == 6, otpRequested, !busy {
                Task {
                    busy = true
                    errorMessage = nil
                    do {
                        try await auth.login(phone: phone, otp: value)
                    } catch {
                        errorMessage = "That code didn't work. Please try again."
                    }
                    busy = false
                }
            }
        }
    }
}
