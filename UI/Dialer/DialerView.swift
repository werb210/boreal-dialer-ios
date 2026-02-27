import SwiftUI

struct DialerView: View {
    @State private var number = ""

    var body: some View {
        VStack {
            TextField("Enter phone number", text: $number)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)
                .padding()

            Button("Call") {
                TwilioManager.shared.makeCall(to: number)
            }
            .padding()
        }
    }
}
