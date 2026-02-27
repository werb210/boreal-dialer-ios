import SwiftUI

struct DialerView: View {

    @State private var number = ""
    @ObservedObject private var callState = VoiceService.shared.getCallState()
    @ObservedObject private var duration = CallDurationManager.shared

    var body: some View {
        VStack(spacing: 20) {

            TextField("Enter phone number", text: $number)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)

            Button("Call") {
                VoiceService.shared.startCall(to: number)
            }

            callStatusView()

        }
        .padding()
    }

    @ViewBuilder
    private func callStatusView() -> some View {
        switch callState.status {
        case .idle:
            EmptyView()
        case .connecting:
            Text("Connecting...")
        case .active:
            VStack {
                Text("On call with \(callState.activeNumber ?? "")")
                Text(duration.formattedDuration)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Button("End Call") {
                    VoiceService.shared.endCall()
                }
                .foregroundColor(.red)
            }
        case .ended:
            Text("Call Ended")
        case .failed(let error):
            Text("Error: \(error)")
                .foregroundColor(.red)
        case .ringing:
            Text("Ringing...")
        }
    }
}
