// BOREAL_DIALER_WATCH_v55
import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchEventStore

    var body: some View {
        NavigationStack {
            Group {
                if let call = store.pendingCall {
                    IncomingCallView(call: call)
                } else if store.events.isEmpty {
                    Text("Nothing yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    List(store.events, id: \.callId) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.subtitle).font(.headline).lineLimit(1)
                            Text(event.title).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Boreal")
        }
        .onAppear { store.start() }
    }
}

struct IncomingCallView: View {
    let call: WatchEvent
    @EnvironmentObject private var store: WatchEventStore

    var body: some View {
        VStack(spacing: 10) {
            Text(call.subtitle).font(.headline).lineLimit(2)
            Text("Incoming call").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    store.send(.decline)
                } label: {
                    Image(systemName: "phone.down.fill")
                }
                .tint(.red)

                Button {
                    store.send(.answer)
                } label: {
                    Image(systemName: "phone.fill")
                }
                .tint(.green)
            }
            // Answering moves the call to the phone; say so rather than letting
            // someone raise a watch to their ear.
            Text("Answers on your phone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
