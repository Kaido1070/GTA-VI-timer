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

    static func apply(settings: TimerSettings, requestPermission: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        let events = ReminderPlan.events(settings: settings, now: .now)
        // Remove obsolete reminders even if permission was subsequently revoked.
        center.removePendingNotificationRequests(withIdentifiers: ReminderPlan.identifiers)
        center.removeDeliveredNotifications(withIdentifiers: ReminderPlan.identifiers)
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
    static func start(settings: TimerSettings) async throws {
        let now = Date()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw Failure.disabled }
        guard LiveCountdownEligibility.allows(target: settings.targetDate(), now: now) else { throw Failure.outsideFinalHours }
        await stop()
        let state = LiveCountdownAttributes.ContentState(target: settings.targetDate(), startedAt: now)
        _ = try Activity.request(attributes: LiveCountdownAttributes(name: settings.name),
                                 content: ActivityContent(state: state, staleDate: state.target), pushType: nil)
    }
    static func stop() async {
        for activity in Activity<LiveCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    static func reconcile(settings: TimerSettings) async {
        for activity in Activity<LiveCountdownAttributes>.activities {
            if activity.attributes.name != settings.name || activity.content.state.target != settings.targetDate() || activity.content.state.target <= .now {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
