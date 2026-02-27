import SwiftUI

struct MessagesView: View {

    @ObservedObject var service = ConversationsService.shared
    @State private var messageText = ""

    var body: some View {

        VStack {

            ScrollView {
                ForEach(service.messages) { msg in
                    VStack(alignment: .leading) {
                        Text(msg.body)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, alignment: msg.author == "me" ? .trailing : .leading)
                }
            }

            HStack {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    service.sendMessage(messageText)
                    messageText = ""
                }
            }
            .padding()
        }
        .padding()
    }
}
