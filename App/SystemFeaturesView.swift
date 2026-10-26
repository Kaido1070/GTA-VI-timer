import SwiftUI
import ActivityKit
import UserNotifications

// Compact iOS features section shown inside Settings.
struct SystemFeaturesSection: View {
    let settings: TimerSettings
    @State private var running = false
    @State private var busy = false
    @State private var message: String?
    @State private var permission = "…"

    var body: some View {
        Section("مزايا iOS") {
            if LiveCountdownEligibility.allows(target: settings.targetDate(), now: .now) {
                Button("بدء النشاط المباشر", action: start).disabled(busy)
            } else {
                LabeledContent("النشاط المباشر", value: "آخر 8 ساعات")
            }
            if running {
                Button("إنهاء النشاط المباشر") {
                    Task { await LiveCountdownController.stop(); running = false }
                }.disabled(busy)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            LabeledContent("Siri", value: "«الوقت المتبقي للموعد»")
            LabeledContent("إذن التنبيهات", value: permission)
            Link("فتح إعدادات iOS للتطبيق", destination: URL(string: UIApplication.openSettingsURLString)!)
        }
        .task {
            running = LiveCountdownController.isRunning
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral: permission = "مسموح"
            case .denied: permission = "غير مسموح"
            default: permission = "لم يُطلب"
            }
        }
    }

    private func start() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await LiveCountdownController.start(settings: settings); running = true; message = nil }
            catch { message = error.localizedDescription }
        }
    }
}
