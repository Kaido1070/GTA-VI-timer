import AppIntents
import WidgetKit

struct RefreshCountdownIntent: AppIntent {
    static var title: LocalizedStringResource = "تحديث العدّاد"
    static var description = IntentDescription("إعادة قراءة الإعدادات المحلية وتحديث الودجت.")
    func perform() async throws -> some IntentResult {
        _ = try SettingsStore.available().load()
        WidgetCenter.shared.reloadTimelines(ofKind: "GTAVITimerWidget")
        return .result()
    }
}

struct GetRemainingIntent: AppIntent {
    static var title: LocalizedStringResource = "الوقت المتبقي للموعد"
    static var description = IntentDescription("قراءة المدة الفعلية المتبقية من إعداداتك المحلية.")
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let settings = try SettingsStore.available().load()
        let remaining = Remaining(target: settings.targetDate(), now: .now)
        let message = remaining.summary(name: settings.name)
        return .result(value: message, dialog: IntentDialog("\(message)"))
    }
}

enum TimerDestination: String, AppEnum {
    case countdown
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "شاشة العدّاد")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.countdown: "العدّاد"]
}

struct OpenTimerIntent: OpenIntent {
    static var title: LocalizedStringResource = "فتح GTA VI Timer"
    static var openAppWhenRun = true
    @Parameter(title: "الوجهة") var target: TimerDestination
    init() { target = .countdown }
    func perform() async throws -> some IntentResult { .result() }
}
