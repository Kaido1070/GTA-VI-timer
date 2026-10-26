import SwiftUI
import WidgetKit
import AppIntents

struct TimerEntry: TimelineEntry {
    let date: Date
    let countdown: Countdown?
    var storageError = false
}

/// Reads the app's countdowns from the shared container.
enum WidgetData {
    struct Result { var list: [Countdown] = []; var shared = false; var storageError = false }
    static func read() -> Result {
        do { return Result(list: try SettingsStore.shared().load(), shared: true) }
        catch SettingsStore.Failure.groupUnavailable { return Result() }
        catch { return Result(shared: true, storageError: true) }
    }
    static func timeline(_ entry: TimerEntry) -> Timeline<TimerEntry> {
        guard let countdown = entry.countdown else {
            return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(3600)))
        }
        let entries = CountdownSchedule.dates(now: entry.date, target: countdown.targetDate()).map {
            TimerEntry(date: $0, countdown: countdown, storageError: entry.storageError)
        }
        return Timeline(entries: entries, policy: .after(entry.date.addingTimeInterval(6 * 3600)))
    }
}

/// The original widget kind (static, as in 1.x): always GTA VI, so widgets
/// already on the screen keep working unchanged.
struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry { TimerEntry(date: .now, countdown: .gtaVI) }
    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        completion(WidgetData.timeline(read()))
    }
    private func read() -> TimerEntry {
        TimerEntry(date: .now, countdown: .gtaVI)
    }
}

/// The configurable kind: pick an app countdown or type one in Edit Widget.
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimerEntry { TimerEntry(date: .now, countdown: .gtaVI) }
    func snapshot(for configuration: SelectCountdownIntent, in context: Context) async -> TimerEntry {
        let entry = read(configuration)
        // The widget gallery shows an example when there is nothing to show yet.
        return entry.countdown == nil && context.isPreview ? TimerEntry(date: .now, countdown: .gtaVI) : entry
    }
    func timeline(for configuration: SelectCountdownIntent, in context: Context) async -> Timeline<TimerEntry> {
        WidgetData.timeline(read(configuration))
    }
    private func read(_ configuration: SelectCountdownIntent) -> TimerEntry {
        let data = WidgetData.read()
        // A chosen countdown wins (live copy if reachable, else the one stored
        // in the widget), then this widget's own fields, then the soonest one.
        if configuration.countdown != nil {
            return TimerEntry(date: .now, countdown: CountdownLookup.find(configuration.countdown, in: data.list),
                              storageError: data.storageError)
        }
        if let manual = configuration.manualCountdown { return TimerEntry(date: .now, countdown: manual) }
        return TimerEntry(date: .now, countdown: CountdownLookup.next(in: data.list), storageError: data.storageError)
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

private let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge,
                                        .accessoryRectangular, .accessoryCircular, .accessoryInline]

struct TimerWidget: Widget {
    let kind = "GTAVITimerWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { TimerWidgetView(entry: $0) }
            .configurationDisplayName("GTA VI")
            .description("عدّاد GTA VI.")
            .supportedFamilies(families)
            .contentMarginsDisabled()
    }
}

struct CustomTimerWidget: Widget {
    let kind = "AnyTimerCustomWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCountdownIntent.self, provider: Provider()) { TimerWidgetView(entry: $0) }
            .configurationDisplayName("AnyTimer")
            .description("اضغط مطولًا > تحرير الأداة لاختيار أي عدّاد من التطبيق.")
            .supportedFamilies(families)
            .contentMarginsDisabled()
    }
}


@main
struct CountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimerWidget()
        CustomTimerWidget()
        LiveCountdownWidget()
        if #available(iOS 18.0, *) { TimerControl() }
    }
}
