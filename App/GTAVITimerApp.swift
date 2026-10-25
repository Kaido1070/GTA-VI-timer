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
    @State private var localOnly = false
    private let turquoise = Color(red: 0.26, green: 0.76, blue: 0.80)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange).padding()
                    }
                    if localOnly {
                        Text("الحفظ داخل التطبيق فقط. الودجت يستخدم GTA VI و19 نوفمبر 2026 والصورة المضمّنة حتى تتوفر مشاركة App Group.")
                            .font(.footnote).foregroundStyle(.secondary).padding(10)
                            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14))
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
                        VStack(spacing: 16) {
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

                            HStack {
                                DaysArtworkCard(settings: settings, remaining: remaining)
                                    .frame(width: 160, height: 160)
                                Spacer()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("بطاقتك المصغّرة").font(.headline)
                                    Text("أضف الودجت إلى الشاشة الرئيسية أو شاشة القفل.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(.black)
            .navigationTitle("GTA VI Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavigationLink { SystemFeaturesView(settings: settings) } label: { Image(systemName: "sparkles") }
                    .accessibilityLabel("مزايا iOS")
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
        try? await NotificationManager.apply(settings: saved, requestPermission: false)
    }

    private func reload() {
        do {
            let store = try SettingsStore.available()
            settings = try store.load(); localOnly = store.scope == .applicationOnly; error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}
