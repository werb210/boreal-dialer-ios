import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct BorealCallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "phone.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.handle).font(.headline).lineLimit(1)
                    Text(context.state.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.startedAt, style: .timer).monospacedDigit().font(.headline)
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "phone.fill").foregroundStyle(.green) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.startedAt, style: .timer).monospacedDigit() }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.handle).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.status).font(.caption).foregroundStyle(.secondary) }
            } compactLeading: {
                Image(systemName: "phone.fill").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer).monospacedDigit()
            } minimal: {
                Image(systemName: "phone.fill").foregroundStyle(.green)
            }
        }
    }
}

@main
struct BorealDialerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) { BorealCallLiveActivity() }
        BorealDialerWidget()
    }
}
