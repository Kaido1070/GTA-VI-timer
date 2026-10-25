import Foundation

struct TimerSettings: Codable, Equatable {
    var name = "GTA VI"
    var year = 2026
    var month = 11
    var day = 19
    var imageFilename: String?
    var reminders: ReminderMode?
    var reminderMode: ReminderMode { reminders ?? .off }

    // Persist a civil date, never an absolute UTC timestamp. Re-evaluate in the
    // device's current timezone, including after travel / a timezone change.
    func targetDate(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: targetDate())
        return parts.year == year && parts.month == month && parts.day == day
    }
}

struct Remaining: Equatable {
    let reached: Bool
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    init(target: Date, now: Date) {
        let interval = target.timeIntervalSince(now)
        reached = interval <= 0
        let total = Int(max(0, interval.rounded(.down)))
        days = total / 86_400
        hours = (total % 86_400) / 3_600
        minutes = (total % 3_600) / 60
        seconds = total % 60
    }

    func summary(name: String) -> String {
        reached ? "\(name): وصل الموعد" : "\(name): باقي \(days) يوم و\(hours) ساعة و\(minutes) دقيقة و\(seconds) ثانية."
    }
}

// Updates at full-day countdown boundaries, with hourly timezone refresh
// opportunities. WidgetKit controls delivery; these are requests, not guarantees.
enum CountdownSchedule {
    static func dates(now: Date, target: Date) -> [Date] {
        guard target > now else { return [now] }
        let horizon = min(target, now.addingTimeInterval(3 * 86_400))
        var dates = [now]
        var hour = now.addingTimeInterval(3_600)
        while hour <= horizon { dates.append(hour); hour.addTimeInterval(3_600) }
        let days = Int(target.timeIntervalSince(now) / 86_400)
        var boundary = target.addingTimeInterval(-Double(days) * 86_400 + 0.05)
        while boundary <= horizon {
            if boundary > now { dates.append(boundary) }
            boundary.addTimeInterval(86_400)
        }
        if target <= horizon { dates.append(target) }
        return Array(Set(dates)).sorted()
    }
}
