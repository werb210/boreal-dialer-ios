import SwiftUI
import SwiftData

struct CallHistoryView: View {

    @Query(sort: \CallLog.timestamp, order: .reverse)
    var calls: [CallLog]

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
