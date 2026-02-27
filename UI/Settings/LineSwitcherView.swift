import SwiftUI

struct LineSwitcherView: View {

    @ObservedObject var manager = LineManager.shared

    var body: some View {
        List {
            ForEach(manager.availableLines) { line in
                Button {
                    manager.switchLine(to: line)
                } label: {
                    HStack {
                        Text(line.displayName)
                        if manager.activeLine == line {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .navigationTitle("Select Line")
    }
}
