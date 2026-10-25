import XCTest
@testable import GTAVITimer

final class SystemIntegrationTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    func testExistingSettingsMigrateWithNotificationsOff() throws {
        let json = Data(#"{"name":"GTA VI","year":2026,"month":11,"day":19}"#.utf8)
        let value = try JSONDecoder().decode(TimerSettings.self, from: json)
        XCTAssertEqual(value.reminderMode, .off)
        XCTAssertEqual(value.day, 19)
    }
    func testOptInOnlyAndPastMilestonesSkipped() {
        var settings = TimerSettings()
        let target = settings.targetDate(timeZone: utc)
        XCTAssertTrue(ReminderPlan.events(settings: settings, now: target.addingTimeInterval(-10 * 86400), timeZone: utc).isEmpty)
        settings.reminders = .milestones
        let events = ReminderPlan.events(settings: settings, now: target.addingTimeInterval(-2 * 86400), timeZone: utc)
        XCTAssertEqual(events.map(\.identifier), ["gtavi.day", "gtavi.arrival"])
        XCTAssertEqual(events.last?.date, target)
        XCTAssertTrue(ReminderPlan.events(settings: settings, now: target, timeZone: utc).isEmpty)
        settings.reminders = .arrival
        XCTAssertEqual(ReminderPlan.events(settings: settings, now: target.addingTimeInterval(-10 * 86400), timeZone: utc).count, 1)
    }
    func testReminderCalendarDaysAcrossDST() {
        var settings = TimerSettings()
        settings.year = 2026; settings.month = 3; settings.day = 9; settings.reminders = .milestones
        let zone = TimeZone(identifier: "America/New_York")!
        let target = settings.targetDate(timeZone: zone)
        let events = ReminderPlan.events(settings: settings, now: target.addingTimeInterval(-10 * 86400), timeZone: zone)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(target.timeIntervalSince(events[1].date), 23 * 3600)
    }
    func testLiveActivityUsesOnlyFinalEightHours() {
        let target = TimerSettings().targetDate(timeZone: utc)
        XCTAssertFalse(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(-86400)))
        XCTAssertTrue(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(-8 * 3600)))
        XCTAssertTrue(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(-1)))
        XCTAssertFalse(LiveCountdownEligibility.allows(target: target, now: target))
        XCTAssertFalse(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(1)))
    }
    func testSpokenCountdownNeverBecomesNegative() {
        let target = TimerSettings().targetDate(timeZone: utc)
        XCTAssertEqual(Remaining(target: target, now: target).summary(name: "GTA VI"), "GTA VI: وصل الموعد")
        XCTAssertFalse(Remaining(target: target, now: target.addingTimeInterval(-90061)).summary(name: "GTA VI").contains("-"))
    }
}
