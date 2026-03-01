import SwiftUI

struct CallHistoryView: View {

    @ObservedObject private var store = CallLogStore.shared

    var body: some View {
        List(store.logs) { log in
            VStack(alignment: .leading, spacing: 4) {

                Text(log.direction.capitalized)
                    .font(.headline)

                Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text("\(Int(log.duration))s")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}
