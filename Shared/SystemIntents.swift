import AppIntents
import WidgetKit

/// A countdown as the widget stores it. The identifier carries the whole
/// countdown (minus any photo), so the widget can draw it without reading the
/// app's data — essential when signing has no App Group to share it.
struct CountdownEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "عدّاد")
    static var defaultQuery = CountdownQuery()
    let id: String
    let countdown: Countdown
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(countdown.name)") }

    init(_ countdown: Countdown) {
        var portable = countdown
        portable.imageFilename = nil
        self.countdown = portable
        id = Self.prefix + ((try? JSONEncoder().encode(portable).base64EncodedString()) ?? countdown.id.uuidString)
    }

    init?(id: String) {
        guard id.hasPrefix(Self.prefix), let data = Data(base64Encoded: String(id.dropFirst(Self.prefix.count))),
              let countdown = try? JSONDecoder().decode(Countdown.self, from: data), countdown.isValid else { return nil }
        self.id = id
        self.countdown = countdown
    }
    private static let prefix = "c1:"
}

struct CountdownQuery: EntityQuery {
    private func all() -> [Countdown] { (try? SettingsStore.available().load()) ?? [] }
    func entities(for identifiers: [String]) async throws -> [CountdownEntity] {
        let list = all()
        return identifiers.compactMap { id in
            CountdownEntity(id: id) ?? list.first { $0.id.uuidString == id }.map(CountdownEntity.init)
        }
    }
    func suggestedEntities() async throws -> [CountdownEntity] { all().map(CountdownEntity.init) }
}

enum CountdownLookup {
    /// The soonest countdown that hasn't arrived yet, else the first one.
    static func next(in list: [Countdown], now: Date = .now) -> Countdown? {
        list.filter { $0.targetDate() > now }.min { $0.targetDate() < $1.targetDate() } ?? list.first
    }
    /// The live copy when the app's data is reachable, else the stored one.
    static func find(_ entity: CountdownEntity?, in list: [Countdown]) -> Countdown? {
        guard let entity else { return next(in: list) }
        return list.first { $0.id == entity.countdown.id } ?? entity.countdown
    }
}

struct SelectCountdownIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "اختيار العدّاد"
    static var description = IntentDescription("اختر عدّادًا من التطبيق، أو اكتب الاسم والتاريخ هنا مباشرة.")
    @Parameter(title: "عدّاد من التطبيق") var countdown: CountdownEntity?
    // Set the countdown right here when the widget can't read the app's data
    // (signing without an App Group); also handy for a one-off widget.
    @Parameter(title: "أو اسم جديد") var name: String?
    @Parameter(title: "التاريخ والوقت") var date: Date?
    @Parameter(title: "الألوان", default: .gold) var theme: WidgetTheme
    @Parameter(title: "الخط", default: .rounded) var font: FontChoice
    @Parameter(title: "إظهار الساعات والدقائق والثواني", default: true) var showClock: Bool
    init() {}

    /// A countdown built from this widget's own fields, if a date was set.
    var manualCountdown: Countdown? {
        guard let date else { return nil }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var value = Countdown(id: Self.manualID, name: trimmed.isEmpty ? "Countdown" : String(trimmed.prefix(80)), target: date)
        value.style = theme.style
        value.style.font = font
        value.style.showClock = showClock
        value.style.imageMode = .hidden
        return value
    }
    private static let manualID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11E")!
}

enum WidgetTheme: String, AppEnum {
    case gold, midnight, purple, ocean, forest, crimson, light, rose, sunset
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "الألوان")
    static var caseDisplayRepresentations: [WidgetTheme: DisplayRepresentation] = [
        .gold: "ذهبي", .midnight: "أسود", .purple: "بنفسجي", .ocean: "أزرق", .forest: "أخضر",
        .crimson: "أحمر", .light: "فاتح", .rose: "وردي", .sunset: "برتقالي",
    ]
    var style: CountdownStyle {
        switch self {
        case .gold: return CountdownStyle(background: "#14161F", text: "#FFFFFF", accent: "#D6A84E")
        case .midnight: return CountdownStyle(background: "#000000", text: "#FFFFFF", accent: "#FFFFFF")
        case .purple: return CountdownStyle(background: "#1B1036", text: "#FFFFFF", accent: "#FF9EC7")
        case .ocean: return CountdownStyle(background: "#0B1E3F", text: "#E8F1FF", accent: "#5AC8FA")
        case .forest: return CountdownStyle(background: "#0F2A1D", text: "#EAF7EE", accent: "#34C759")
        case .crimson: return CountdownStyle(background: "#3A0D0D", text: "#FFECEC", accent: "#FF453A")
        case .light: return CountdownStyle(background: "#F5F0E6", text: "#1C1C1E", accent: "#B8860B")
        case .rose: return CountdownStyle(background: "#FFFFFF", text: "#111111", accent: "#FF2D55")
        case .sunset: return CountdownStyle(background: "#2B1A00", text: "#FFF4E0", accent: "#FF9F0A")
        }
    }
}

extension FontChoice: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "الخط")
    static var caseDisplayRepresentations: [FontChoice: DisplayRepresentation] = [
        .system: "System", .rounded: "Rounded", .serif: "Serif", .mono: "Mono",
        .avenir: "Avenir Next", .futura: "Futura", .didot: "Didot", .bodoni: "Bodoni",
        .baskerville: "Baskerville", .georgia: "Georgia", .optima: "Optima", .gillSans: "Gill Sans",
        .copperplate: "Copperplate", .americanTypewriter: "Typewriter", .snellRoundhand: "Snell Roundhand",
        .markerFelt: "Marker Felt", .chalkboard: "Chalkboard", .noteworthy: "Noteworthy",
    ]
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
