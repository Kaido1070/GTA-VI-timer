import SwiftUI
import ActivityKit
import UserNotifications

/// App-wide settings: the app's own look and a compact iOS features summary.
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var appearance: AppAppearance
    let countdowns: [Countdown]
    @State private var permission = "…"
    @State private var running = false
    @State private var sharing = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("مظهر التطبيق") {
                    ColorPicker("لون التطبيق", selection: hexBinding(\.accent), supportsOpacity: false)
                    ColorPicker("خلفية التطبيق", selection: hexBinding(\.background), supportsOpacity: false)
                    Picker("حجم البطاقات", selection: $appearance.cardSize) {
                        ForEach(AppAppearance.CardSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("استعادة الافتراضي") { appearance = AppAppearance() }
                }
                Section("مزايا iOS") {
                    LabeledContent("العدّادات", value: "\(countdowns.count)")
                    LabeledContent("الودجت", value: sharing ? "متصل" : "يحتاج App Group")
                    LabeledContent("Siri", value: "«الوقت المتبقي للموعد»")
                    LabeledContent("إذن التنبيهات", value: permission)
                    if running {
                        Button("إنهاء النشاط المباشر") {
                            Task { await LiveCountdownController.stop(); running = false }
                        }
                    }
                    Link("فتح إعدادات iOS للتطبيق", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } }
            }
            .onChange(of: appearance) { _, value in
                do { try SettingsStore.available().saveAppearance(value); error = nil }
                catch { self.error = error.localizedDescription }
            }
            .task {
                running = LiveCountdownController.isRunning
                sharing = (try? SettingsStore.available().scope) == .shared
                switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
                case .authorized, .provisional, .ephemeral: permission = "مسموح"
                case .denied: permission = "غير مسموح"
                default: permission = "لم يُطلب"
                }
            }
        }
        .tint(Color(hex: appearance.accent))
    }

    private func hexBinding(_ key: WritableKeyPath<AppAppearance, String>) -> Binding<Color> {
        Binding(get: { Color(hex: appearance[keyPath: key]) }, set: { appearance[keyPath: key] = $0.hex })
    }
}
