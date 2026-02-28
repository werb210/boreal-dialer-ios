import SwiftUI

struct CallHistoryView: View {

    @ObservedObject private var store = CallLogStore.shared

    var body: some View {
        List(store.logs) { log in
            VStack(alignment: .leading, spacing: 4) {

                Text(log.phoneNumber)
                    .font(.headline)

                Text("\(log.direction.rawValue.capitalized) • \(log.result.rawValue.capitalized)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text("\(log.durationSeconds)s")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}
