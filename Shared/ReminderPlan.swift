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
    static let identifiers = ["gtavi.week", "gtavi.day", "gtavi.arrival"]
    static func events(settings: TimerSettings, now: Date, timeZone: TimeZone = .current) -> [PlannedReminder] {
        guard settings.reminderMode != .off else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let target = settings.targetDate(timeZone: timeZone)
        var offsets = [0]
        if settings.reminderMode == .milestones { offsets = [-7, -1, 0] }
        return offsets.compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: target), date > now else { return nil }
            let suffix = offset == -7 ? "week" : offset == -1 ? "day" : "arrival"
            let body = offset == 0 ? "وصل الموعد" : offset == -1 ? "باقي يوم على الموعد المحلي" : "باقي أسبوع على الموعد المحلي"
            return PlannedReminder(identifier: "gtavi.\(suffix)", date: date, title: settings.name, body: body)
        }
    }
}
