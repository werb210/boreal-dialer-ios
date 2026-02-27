import SwiftUI

struct IncomingCallView: View {

    let caller: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {

        VStack(spacing: 40) {

            Text("Incoming Call")
                .font(.title)

            Text(caller)
                .font(.largeTitle)
                .bold()

            HStack(spacing: 60) {

                Button(action: onDecline) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 80, height: 80)
                        .overlay(Image(systemName: "phone.down.fill")
                            .foregroundColor(.white)
                            .font(.title))
                }

                Button(action: onAccept) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 80, height: 80)
                        .overlay(Image(systemName: "phone.fill")
                            .foregroundColor(.white)
                            .font(.title))
                }
            }
        }
        .padding()
    }
}
