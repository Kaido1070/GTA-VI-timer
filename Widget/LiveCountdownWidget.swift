import SwiftUI
import WidgetKit
import ActivityKit

struct LiveCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveCountdownAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(Color(hex: context.attributes.accent))
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.attributes.name).font(.headline).lineLimit(1)
                    countdown(context, font: .title2.bold())
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "gtavitimer://countdown/\(context.attributes.countdownID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hourglass").foregroundStyle(Color(hex: context.attributes.accent))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.name).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    countdown(context, font: .title.bold()).padding(.vertical, 4)
                }
            } compactLeading: {
                Image(systemName: "hourglass").foregroundStyle(Color(hex: context.attributes.accent))
            } compactTrailing: {
                countdown(context, font: .caption2.monospacedDigit()).frame(width: 62)
            } minimal: {
                Image(systemName: context.isStale ? "checkmark" : "hourglass").foregroundStyle(Color(hex: context.attributes.accent))
            }
            .widgetURL(URL(string: "gtavitimer://countdown/\(context.attributes.countdownID)"))
            .keylineTint(Color(hex: context.attributes.accent))
        }
    }
    @ViewBuilder private func countdown(_ context: ActivityViewContext<LiveCountdownAttributes>, font: Font) -> some View {
        if context.isStale {
            Text("وصل الموعد").font(font).foregroundStyle(Color(hex: context.attributes.accent))
        } else {
            // The system renders this timer; no background one-second work.
            Text(timerInterval: context.state.startedAt...context.state.target, countsDown: true)
                .font(font).monospacedDigit().foregroundStyle(Color(hex: context.attributes.accent))
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}
