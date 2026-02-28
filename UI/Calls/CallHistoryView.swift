import SwiftUI
import SwiftData

struct LegacyCallHistoryView: View {

    @Query(sort: \PersistedCallLog.timestamp, order: .reverse)
    var calls: [PersistedCallLog]

    var body: some View {
        List(calls) { call in
            VStack(alignment: .leading) {
                Text(call.phoneNumber)
                    .font(.headline)
                Text(call.status)
                    .font(.subheadline)
                Text(call.timestamp.formatted())
                    .font(.caption)
            }
        }
        .navigationTitle("Call History")
    }
}
