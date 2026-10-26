import SwiftUI
import WidgetKit
import AppIntents

struct TimerEntry: TimelineEntry {
    let date: Date
    let countdown: Countdown?
    var storageError = false
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimerEntry { TimerEntry(date: .now, countdown: .gtaVI) }
    func snapshot(for configuration: SelectCountdownIntent, in context: Context) async -> TimerEntry {
        let entry = read(configuration)
        // The widget gallery shows an example when there is nothing to show yet.
        return entry.countdown == nil && context.isPreview ? TimerEntry(date: .now, countdown: .gtaVI) : entry
    }
    func timeline(for configuration: SelectCountdownIntent, in context: Context) async -> Timeline<TimerEntry> {
        let initial = read(configuration)
        guard let countdown = initial.countdown else {
            return Timeline(entries: [initial], policy: .after(initial.date.addingTimeInterval(3600)))
        }
        let entries = CountdownSchedule.dates(now: initial.date, target: countdown.targetDate()).map {
            TimerEntry(date: $0, countdown: countdown, storageError: initial.storageError)
        }
        return Timeline(entries: entries, policy: .after(initial.date.addingTimeInterval(6 * 3600)))
    }
    private func read(_ configuration: SelectCountdownIntent) -> TimerEntry {
        var list: [Countdown] = []
        var storageError = false
        do { list = try SettingsStore.shared().load() }
        // Personal signing without an App Group: the widget can't see the app's
        // countdowns, but can still show one set in Edit Widget.
        catch SettingsStore.Failure.groupUnavailable {}
        catch { storageError = true }
        // An explicitly chosen app countdown wins, then this widget's own fields,
        // then the soonest app countdown.
        if let entity = configuration.countdown, let match = list.first(where: { $0.id.uuidString == entity.id }) {
            return TimerEntry(date: .now, countdown: match, storageError: storageError)
        }
        if let manual = configuration.manualCountdown { return TimerEntry(date: .now, countdown: manual) }
        return TimerEntry(date: .now, countdown: CountdownLookup.next(in: list), storageError: storageError)
    }
}

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry
    var body: some View {
        Group {
            if let countdown = entry.countdown {
                content(countdown)
            } else if family == .accessoryInline {
                Label("AnyTimer", systemImage: "hourglass")
            } else {
                EmptyCountdownView(compact: family == .accessoryCircular || family == .accessoryRectangular)
            }
        }
        .containerBackground(for: .widget) {
            if let countdown = entry.countdown { countdown.style.backgroundColor } else { Color.black }
        }
        .widgetURL(URL(string: "gtavitimer://countdown/\(entry.countdown?.id.uuidString ?? "")"))
    }

    @ViewBuilder private func content(_ countdown: Countdown) -> some View {
        let remaining = Remaining(target: countdown.targetDate(), now: entry.date)
        switch family {
        case .accessoryInline:
            Label(remaining.reached ? "\(countdown.name): Now" : "\(countdown.name): \(remaining.days)d left", systemImage: "hourglass")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if remaining.reached { Image(systemName: "checkmark").font(.title2) }
                    else {
                        Text(verbatim: String(remaining.days)).font(countdown.style.font.font(23)).minimumScaleFactor(0.5).lineLimit(1)
                        Text("DAYS").font(.system(size: 9, weight: .bold))
                    }
                }.padding(5)
            }
            .accessibilityLabel(remaining.reached ? "\(countdown.name), now" : "\(countdown.name), \(remaining.days) days left")
        case .accessoryRectangular:
            LockRectangularView(countdown: countdown, now: entry.date, storageError: entry.storageError)
        default:
            HomeCountdownView(countdown: countdown, now: entry.date, family: family, storageError: entry.storageError)
        }
    }
}

struct TimerWidget: Widget {
    let kind = "GTAVITimerWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCountdownIntent.self, provider: Provider()) { TimerWidgetView(entry: $0) }
            .configurationDisplayName("AnyTimer")
            .description("اختر أي عدّاد لعرضه. اضغط مطولًا على الودجت > تحرير لتغيير العدّاد.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
            .contentMarginsDisabled()
    }
}


@main
struct CountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimerWidget()
        LiveCountdownWidget()
        if #available(iOS 18.0, *) { TimerControl() }
    }
}
