import SwiftUI
import CoreData

struct CallHistoryView: View {

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CallEntity.startedAt, ascending: false)],
        animation: .default
    )
    private var calls: FetchedResults<CallEntity>

    var body: some View {
        List(calls, id: \.id) { call in
            VStack(alignment: .leading) {
                Text(call.number)
                    .font(.headline)
                Text(call.status)
                    .font(.subheadline)
                Text(call.startedAt.formatted())
                    .font(.caption)
            }
        }
        .navigationTitle("Call History")
    }
}
