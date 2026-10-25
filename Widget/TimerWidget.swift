import SwiftUI
import WidgetKit
import AppIntents

struct TimerEntry: TimelineEntry {
    let date: Date
    let settings: TimerSettings
    var storageError = false
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry { TimerEntry(date: .now, settings: TimerSettings()) }
    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let initial = read()
        let entries = CountdownSchedule.dates(now: initial.date, target: initial.settings.targetDate()).map {
            TimerEntry(date: $0, settings: initial.settings, storageError: initial.storageError)
        }
        completion(Timeline(entries: entries, policy: .after(initial.date.addingTimeInterval(6 * 3600))))
    }
    private func read() -> TimerEntry {
        do { return TimerEntry(date: .now, settings: try SettingsStore.shared().load()) }
        // Personal signing without an App Group is expected: the defaults are the
        // intended target, so don't flag it on the widget. Warn only on bad data.
        catch SettingsStore.Failure.groupUnavailable { return TimerEntry(date: .now, settings: TimerSettings()) }
        catch { return TimerEntry(date: .now, settings: TimerSettings(), storageError: true) }
    }
}

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry
    var remaining: Remaining { Remaining(target: entry.settings.targetDate(), now: entry.date) }
    var body: some View {
        Group {
            if family == .accessoryInline {
                Label(remaining.reached ? "وصل الموعد" : "\(entry.settings.name): \(remaining.days) يوم", systemImage: "hourglass")
            } else if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        if remaining.reached { Image(systemName: "checkmark").font(.title2) }
                        else {
                            Text("\(remaining.days)").font(.system(size: 23, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                            Text("يوم").font(.caption2)
                        }
                    }.padding(5)
                }
                .accessibilityLabel(remaining.reached ? "وصل الموعد" : "\(remaining.days) يوم متبقٍ")
            } else if family == .accessoryRectangular {
                LockRectangularView(settings: entry.settings, remaining: remaining, storageError: entry.storageError)
            } else if family == .systemSmall {
                DaysArtworkCard(settings: entry.settings, remaining: remaining)
                    .overlay(alignment: .topTrailing) { refreshButton.padding(6) }
                    .overlay(alignment: .topLeading) {
                        if entry.storageError { Image(systemName: "exclamationmark.triangle.fill").padding(8).foregroundStyle(.orange) }
                    }
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ArtworkView(settings: entry.settings, maximumPixelSize: 800, blurredFill: false)
                        LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .center)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.settings.name).font(.title2.bold())
                            Text(entry.settings.targetDate(), format: .dateTime.day().month().year()).font(.caption)
                            Spacer()
                            Text(remaining.reached ? "وصل الموعد" : "\(remaining.days) يوم")
                                .font(.system(size: family == .systemLarge ? 52 : 36, weight: .heavy, design: .rounded))
                                .monospacedDigit().padding(8)
                                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            if entry.storageError { Text("تعذّرت قراءة الإعدادات — افتراضية").font(.caption) }
                        }
                        .foregroundStyle(.white).shadow(color: .black, radius: 2).padding(16)
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 10) {
                            refreshButton
                            Link(destination: URL(string: "gtavitimer://settings")!) {
                                Image(systemName: "gearshape.fill").padding(5).background(.black.opacity(0.5), in: Circle())
                            }.accessibilityLabel("إعدادات العدّاد")
                        }.foregroundStyle(.white).padding(8)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
        }
        .containerBackground(for: .widget) { Color.black }
        .widgetURL(URL(string: "gtavitimer://countdown"))
    }
    private var refreshButton: some View {
        Button(intent: RefreshCountdownIntent()) {
            Image(systemName: "arrow.clockwise").font(.caption.bold()).foregroundStyle(.white)
                .padding(6).background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("تحديث العدّاد من الإعدادات المحلية")
    }
}

struct TimerWidget: Widget {
    let kind = "GTAVITimerWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { TimerWidgetView(entry: $0) }
            .configurationDisplayName("GTA VI Timer")
            .description("الأيام الكاملة المتبقية حتى بداية الموعد المحلي.")
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
