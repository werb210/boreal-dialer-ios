import SwiftUI

struct LineSwitcherView: View {

    @ObservedObject var manager = LineManager.shared
    // DIALER_v850_KS_CRM - switching line ends the call in progress, so it waits until the call is over.
    @ObservedObject private var voiceEngine = VoiceEngine.shared

    var body: some View {
        List {
            Section {
                ForEach(manager.availableLines) { line in
                    Button {
                        manager.switchLine(to: line)
                    } label: {
                        HStack {
                            Text(line.name)
                                .foregroundColor(line.silo == .ks ? Theme.keystoneText : nil) // DIALER_v850_KS_CRM
                            if manager.activeLine == line {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(voiceEngine.isOnCall)
                }
            } footer: {
                Text(voiceEngine.isOnCall
                     ? "Finish the call in progress to change line."
                     : "Calls, texts, contacts and call history follow the line you pick.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Select Line")
    }
}
