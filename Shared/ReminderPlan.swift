import Foundation

enum ReminderMode: String, Codable, CaseIterable, Identifiable {
    case off, arrival, milestones
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "بدون تنبيهات"
        case .arrival: return "عند الموعد فقط"
        case .milestones: return "قبل أسبوع ويوم وعند الموعد"
        }
    }
}

struct PlannedReminder: Equatable {
    let identifier: String
    let date: Date
    let title: String
    let body: String
}

enum ReminderPlan {
    /// Every pending request this app owns starts with this prefix.
    static let prefix = "anytimer."
    /// Identifiers used by GTA VI Timer 1.x, cleared on upgrade.
    static let legacyIdentifiers = ["gtavi.week", "gtavi.day", "gtavi.arrival"]

    static func events(countdown: Countdown, now: Date, timeZone: TimeZone = .current) -> [PlannedReminder] {
        guard countdown.reminderMode != .off else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let target = countdown.targetDate(timeZone: timeZone)
        var offsets = [0]
        if countdown.reminderMode == .milestones { offsets = [-7, -1, 0] }
        return offsets.compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: target), date > now else { return nil }
            let suffix = offset == -7 ? "week" : offset == -1 ? "day" : "arrival"
            let body = offset == 0 ? "وصل الموعد" : offset == -1 ? "باقي يوم على الموعد" : "باقي أسبوع على الموعد"
            return PlannedReminder(identifier: "\(prefix)\(countdown.id.uuidString).\(suffix)", date: date,
                                   title: countdown.name, body: body)
        }
    }

    static func events(countdowns: [Countdown], now: Date, timeZone: TimeZone = .current) -> [PlannedReminder] {
        // iOS keeps at most 64 pending local notifications per app; soonest first.
        Array(countdowns.flatMap { events(countdown: $0, now: now, timeZone: timeZone) }
            .sorted { $0.date < $1.date }.prefix(60))
    }
}
