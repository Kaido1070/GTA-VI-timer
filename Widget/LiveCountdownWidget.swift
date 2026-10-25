import SwiftUI
import WidgetKit
import ActivityKit

struct LiveCountdownWidget: Widget {
    private let turquoise = Color(red: 0.26, green: 0.76, blue: 0.80)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveCountdownAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(turquoise)
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.attributes.name).font(.headline).lineLimit(1)
                    countdown(context, font: .title2.bold())
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "gtavitimer://countdown"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hourglass").foregroundStyle(turquoise)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.name).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    countdown(context, font: .title.bold()).padding(.vertical, 4)
                }
            } compactLeading: {
                Image(systemName: "hourglass").foregroundStyle(turquoise)
            } compactTrailing: {
                countdown(context, font: .caption2.monospacedDigit()).frame(width: 62)
            } minimal: {
                Image(systemName: context.isStale ? "checkmark" : "hourglass").foregroundStyle(turquoise)
            }
            .widgetURL(URL(string: "gtavitimer://countdown"))
            .keylineTint(turquoise)
        }
    }
    @ViewBuilder private func countdown(_ context: ActivityViewContext<LiveCountdownAttributes>, font: Font) -> some View {
        if context.isStale {
            Text("وصل الموعد").font(font).foregroundStyle(turquoise)
        } else {
            // The system renders this timer; no background one-second work.
            Text(timerInterval: context.state.startedAt...context.state.target, countsDown: true)
                .font(font).monospacedDigit().foregroundStyle(turquoise)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}
