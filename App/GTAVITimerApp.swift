import SwiftUI
import WidgetKit

@main
struct GTAVITimerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView().preferredColorScheme(.dark)
        }
    }
}

struct HomeView: View {
    @Environment(\.scenePhase) private var phase
    @State private var settings = TimerSettings()
    @State private var error: String?
    @State private var editing = false
    private let turquoise = Color(red: 0.26, green: 0.76, blue: 0.80)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange).padding()
                    }
                    ZStack(alignment: .bottomLeading) {
                        ArtworkView(settings: settings)
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(settings.name).font(.largeTitle.bold()).lineLimit(2)
                            Text(settings.targetDate(), format: .dateTime.day().month(.wide).year())
                                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(20)
                    }
                    .aspectRatio(0.95, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28))

                    // Only the visible application refreshes each second.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = Remaining(target: settings.targetDate(), now: context.date)
                        Group {
                            if remaining.reached {
                                Text("وصل الموعد").font(.largeTitle.bold()).frame(maxWidth: .infinity)
                            } else {
                                HStack(spacing: 4) {
                                    unit(remaining.days, "يوم")
                                    unit(remaining.hours, "ساعة")
                                    unit(remaining.minutes, "دقيقة")
                                    unit(remaining.seconds, "ثانية")
                                }
                                .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        .foregroundStyle(turquoise)
                        .padding(.vertical, 24).padding(.horizontal, 12)
                        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                .padding(16)
            }
            .background(.black)
            .navigationTitle("GTA VI Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { editing = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("الإعدادات")
            }
            .sheet(isPresented: $editing) {
                SettingsView(initial: settings) { saved in
                    settings = saved
                    error = nil
                }
            }
            .onAppear(perform: reload)
            .task { await reconcileIntegrations() }
            .onOpenURL { url in
                guard url.scheme == "gtavitimer" else { return }
                editing = url.host == "settings"
            }
            .onChange(of: phase) { _, value in
                if value == .active {
                    reload(); WidgetCenter.shared.reloadAllTimelines()
                    Task { await reconcileIntegrations() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                reload(); WidgetCenter.shared.reloadAllTimelines()
                Task { await reconcileIntegrations() }
            }
        }
        .tint(turquoise)
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text("\(value)").font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func reconcileIntegrations() async {
        guard let saved = try? SettingsStore.available().load() else { return }
        await LiveCountdownController.reconcile(settings: saved)
        // With reminders off, foreground launch should not contact the
        // notification daemon. Explicitly saving Off clears old requests.
        if saved.reminderMode != .off {
            try? await NotificationManager.apply(settings: saved, requestPermission: false)
        }
    }

    private func reload() {
        do {
            let store = try SettingsStore.available()
            settings = try store.load(); error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}
