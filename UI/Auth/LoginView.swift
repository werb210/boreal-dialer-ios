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

    // BOREAL_DIALER_LOGIN_STYLE_v26 - brand palette (navy field, gold + green accents)
    private let navy = Color(red: 0.043, green: 0.122, blue: 0.227)
    private let gold = Color(red: 0.784, green: 0.635, blue: 0.294)

    private func fieldStyle<V: View>(_ v: V) -> some View {
        v.foregroundColor(.white)
            .tint(gold)
            .padding(14)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
    }

    private func submitCode(_ code: String) {
        Task {
            busy = true
            errorMessage = nil
            do {
                try await auth.login(phone: phone, otp: code)
            } catch {
                errorMessage = "That code didn't work. Please try again."
            }
            busy = false
        }
    }

    var body: some View {
        ZStack {
            navy.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Image(systemName: "phone.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(gold)
                Text("Boreal Dialer")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                Text("Sign in with your work number")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                VStack(spacing: 14) {
                    fieldStyle(
                        TextField("Phone", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focused, equals: .phone)
                    )

                    if otpRequested {
                        fieldStyle(
                            TextField("6-digit code", text: $otp)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focused, equals: .code)
                        )
                    }
                }

                Button {
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
                } label: {
                    Text(otpRequested ? "Resend code" : "Send code")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(otpRequested ? Color.white.opacity(0.12) : Color.green)
                        .foregroundColor(otpRequested ? .white : .black)
                        .cornerRadius(12)
                }
                .disabled(busy || phone.isEmpty)

                if otpRequested {
                    Button {
                        submitCode(otp)
                    } label: {
                        Text("Log in")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.green)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                    .disabled(busy || otp.isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear { focused = .phone }
        // Six digits is the whole code - no reason to make anyone tap Login.
        .onChange(of: otp) { value in
            if value.count == 6, otpRequested, !busy {
                submitCode(value)
            }
        }
    }
}
