import SwiftUI
import ActivityKit
import UserNotifications

struct SystemFeaturesView: View {
    let settings: TimerSettings
    @State private var running = false
    @State private var busy = false
    @State private var message: String?
    @State private var permission = "جارٍ التحقق…"

    var body: some View {
        List {
            Section("الأنشطة المباشرة وDynamic Island") {
                Label("عدّاد الساعات الأخيرة", systemImage: "hourglass")
                Text("يمكنك تشغيل عدّاد حي خلال آخر 8 ساعات قبل الموعد. يظهر على شاشة القفل وDynamic Island على الأجهزة الداعمة، وقد يظهر في StandBy. مدة النشاط يحددها النظام ولا يستمر طوال الأسابيع المتبقية.")
                    .font(.footnote).foregroundStyle(.secondary)
                if LiveCountdownEligibility.allows(target: settings.targetDate(), now: .now) {
                    startButton
                } else {
                    Text(Remaining(target: settings.targetDate(), now: .now).reached ? "وصل الموعد" : "يتاح التشغيل في آخر 8 ساعات.")
                        .foregroundStyle(.secondary)
                }
                if running {
                    Button("إنهاء النشاط المباشر") {
                        Task { await LiveCountdownController.stop(); running = false }
                    }.disabled(busy)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            }
            Section("Siri والاختصارات") {
                Label("الوقت المتبقي", systemImage: "waveform")
                Text("من تطبيق الاختصارات أضف إجراء «الوقت المتبقي للموعد» لقراءة العدّاد أو استخدام النتيجة كنص، أو إجراء «فتح GTA VI Timer». لا يحتاج التطبيق خادمًا؛ توفر Siri ولغتها يتبع إعدادات جهازك.")
                    .font(.footnote)
            }
            Section("التنبيهات المحلية") {
                Text("الإذن: \(permission)")
                Text("التذكير المختار: \(settings.reminderMode.title)")
                Text("غيّر التذكير من إعدادات العدّاد. لا يُطلب الإذن إلا عند تفعيل التنبيهات والحفظ. التنبيهات تتبع إعدادات التركيز وملخص الإشعارات، ولا نضمن وصولها في ثانية محددة.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("فتح إعدادات iOS للتطبيق", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
            Section("الودجت ومركز التحكم") {
                Text("الشاشة الرئيسية: صغير ومتوسط وكبير، مع زر تحديث تفاعلي. اضغط على الودجت لفتح العدّاد؛ اضغط على أيقونة الإعدادات في الأحجام الكبيرة لتعديل الموعد.")
                Text("شاشة القفل: مستطيل بصورة وعدد فوقها، ودائري ومختصر نصي. قد يحوّل iOS الصورة إلى لون موحّد.")
                if #available(iOS 18.0, *) {
                    Text("من مركز التحكم > إضافة عنصر تحكم > GTA VI Timer أضف زر فتح العدّاد. يمكن اختياره أيضًا لزر الإجراءات أو أزرار القفل إذا سمح جهازك والنظام بذلك.")
                }
                Text("يدعم ودجت الرئيسية StandBy تلقائيًا على أجهزة iPhone الداعمة. أوضاع الصبغة والألوان والمظهر الشفاف تتبع إعدادات iOS.")
            }
            Section("الجهاز الحالي") {
                Text("iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                Text("تظهر المزايا بحسب إصدار النظام وقدرات الجهاز. لا تحتاج المزايا الأساسية اتصالًا أو تسجيل دخول.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("مزايا iOS")
        .task {
            running = LiveCountdownController.isRunning
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral: permission = "مسموح"
            case .denied: permission = "غير مسموح"
            default: permission = "لم يُطلب بعد"
            }
        }
    }

    @ViewBuilder private var startButton: some View {
        if #available(iOS 26.0, *) {
            Button("بدء النشاط المباشر", action: start).buttonStyle(.glassProminent).disabled(busy)
        } else {
            Button("بدء النشاط المباشر", action: start).buttonStyle(.borderedProminent).disabled(busy)
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
