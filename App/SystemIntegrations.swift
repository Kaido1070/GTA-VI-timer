import ActivityKit
import AppIntents
import UserNotifications
import Foundation

struct CountdownShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetRemainingIntent(), phrases: [
            "كم باقي في \(.applicationName)", "Time remaining in \(.applicationName)"
        ], shortTitle: "الوقت المتبقي", systemImageName: "hourglass")
        AppShortcut(intent: OpenTimerIntent(), phrases: [
            "افتح \(.applicationName)", "Open \(.applicationName)"
        ], shortTitle: "فتح العدّاد", systemImageName: "timer")
    }
}

enum NotificationManager {
    enum Failure: LocalizedError {
        case denied
        var errorDescription: String? { "التنبيهات غير مسموحة. فعّلها من إعدادات iOS إذا رغبت بالتذكير." }
    }

    /// Re-plans reminders for every countdown. Removes stale requests first,
    /// even if permission was subsequently revoked.
    static func apply(countdowns: [Countdown], requestPermission: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        let events = ReminderPlan.events(countdowns: countdowns, now: .now)
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(ReminderPlan.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending + ReminderPlan.legacyIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: ReminderPlan.legacyIdentifiers)
        guard !events.isEmpty else { return }
        let authorization = await center.notificationSettings().authorizationStatus
        if authorization == .notDetermined, requestPermission {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw Failure.denied }
        } else if ![.authorized, .provisional, .ephemeral].contains(authorization) {
            throw Failure.denied
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title; content.body = event.body; content.sound = .default
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
            components.calendar = calendar
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: event.identifier, content: content, trigger: trigger))
        }
    }
}

@MainActor enum LiveCountdownController {
    enum Failure: LocalizedError {
        case disabled, outsideFinalHours
        var errorDescription: String? {
            switch self {
            case .disabled: return "الأنشطة المباشرة غير متاحة أو غير مسموحة. راجع إعدادات التطبيق في iOS."
            case .outsideFinalHours: return "تتاح هذه الميزة خلال آخر 8 ساعات فقط؛ الودجت العادي مناسب للانتظار الطويل."
            }
        }
    }
    static var isRunning: Bool { !Activity<LiveCountdownAttributes>.activities.isEmpty }
    static func start(countdown: Countdown) async throws {
        let now = Date()
        let target = countdown.targetDate()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw Failure.disabled }
        guard LiveCountdownEligibility.allows(target: target, now: now) else { throw Failure.outsideFinalHours }
        await stop()
        let state = LiveCountdownAttributes.ContentState(target: target, startedAt: now)
        let attributes = LiveCountdownAttributes(name: countdown.name, countdownID: countdown.id.uuidString,
                                                 accent: countdown.style.accent)
        _ = try Activity.request(attributes: attributes,
                                 content: ActivityContent(state: state, staleDate: state.target), pushType: nil)
    }
    static func stop() async {
        for activity in Activity<LiveCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    /// Ends an activity whose countdown was deleted, changed or has arrived.
    static func reconcile(countdowns: [Countdown]) async {
        for activity in Activity<LiveCountdownAttributes>.activities {
            let match = countdowns.first { $0.id.uuidString == activity.attributes.countdownID }
            if match == nil || match!.name != activity.attributes.name
                || match!.targetDate() != activity.content.state.target || activity.content.state.target <= .now {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
