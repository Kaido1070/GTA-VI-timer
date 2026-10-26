import AppIntents
import WidgetKit

struct CountdownEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "عدّاد")
    static var defaultQuery = CountdownQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ countdown: Countdown) { id = countdown.id.uuidString; name = countdown.name }
}

struct CountdownQuery: EntityQuery {
    private func all() -> [Countdown] { (try? SettingsStore.available().load()) ?? [] }
    func entities(for identifiers: [String]) async throws -> [CountdownEntity] {
        all().filter { identifiers.contains($0.id.uuidString) }.map(CountdownEntity.init)
    }
    func suggestedEntities() async throws -> [CountdownEntity] { all().map(CountdownEntity.init) }
    func defaultResult() async -> CountdownEntity? { CountdownLookup.next(in: all()).map(CountdownEntity.init) }
}

enum CountdownLookup {
    /// The soonest countdown that hasn't arrived yet, else the first one.
    static func next(in list: [Countdown], now: Date = .now) -> Countdown? {
        list.filter { $0.targetDate() > now }.min { $0.targetDate() < $1.targetDate() } ?? list.first
    }
    static func find(_ entity: CountdownEntity?, in list: [Countdown]) -> Countdown? {
        if let entity, let match = list.first(where: { $0.id.uuidString == entity.id }) { return match }
        return next(in: list)
    }
}

struct SelectCountdownIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "اختيار العدّاد"
    static var description = IntentDescription("اختر العدّاد الذي يظهر في هذا الودجت.")
    @Parameter(title: "العدّاد") var countdown: CountdownEntity?
    init() {}
    init(countdown: CountdownEntity?) { self.countdown = countdown }
}

struct GetRemainingIntent: AppIntent {
    static var title: LocalizedStringResource = "الوقت المتبقي للموعد"
    static var description = IntentDescription("قراءة المدة المتبقية لأحد عدّاداتك.")
    @Parameter(title: "العدّاد") var countdown: CountdownEntity?
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let match = CountdownLookup.find(countdown, in: try SettingsStore.available().load()) else {
            let message = "لا توجد عدّادات بعد."
            return .result(value: message, dialog: IntentDialog("\(message)"))
        }
        let message = Remaining(target: match.targetDate(), now: .now).summary(name: match.name)
        return .result(value: message, dialog: IntentDialog("\(message)"))
    }
}

enum TimerDestination: String, AppEnum {
    case countdown
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "شاشة العدّاد")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.countdown: "العدّادات"]
}

struct OpenTimerIntent: OpenIntent {
    static var title: LocalizedStringResource = "فتح AnyTimer"
    static var openAppWhenRun = true
    @Parameter(title: "الوجهة") var target: TimerDestination
    init() { target = .countdown }
    func perform() async throws -> some IntentResult { .result() }
}
