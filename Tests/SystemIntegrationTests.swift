import XCTest
@testable import GTAVITimer

final class SystemIntegrationTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    func testVersionOneSettingsDecodeAsCountdown() throws {
        let json = Data(#"{"name":"GTA VI","year":2026,"month":11,"day":19}"#.utf8)
        let value = try JSONDecoder().decode(Countdown.self, from: json)
        XCTAssertEqual(value.reminderMode, .off)
        XCTAssertEqual([value.day, value.hour, value.minute], [19, 0, 0])
        XCTAssertEqual(value.style, CountdownStyle())
    }
    func testOptInOnlyAndPastMilestonesSkipped() {
        var countdown = Countdown.gtaVI
        let target = countdown.targetDate(timeZone: utc)
        XCTAssertTrue(ReminderPlan.events(countdown: countdown, now: target.addingTimeInterval(-10 * 86400), timeZone: utc).isEmpty)
        countdown.reminders = .milestones
        let events = ReminderPlan.events(countdown: countdown, now: target.addingTimeInterval(-2 * 86400), timeZone: utc)
        XCTAssertEqual(events.map { $0.identifier.components(separatedBy: ".").last }, ["day", "arrival"])
        XCTAssertTrue(events.allSatisfy { $0.identifier.hasPrefix(ReminderPlan.prefix + countdown.id.uuidString) })
        XCTAssertEqual(events.last?.date, target)
        XCTAssertTrue(ReminderPlan.events(countdown: countdown, now: target, timeZone: utc).isEmpty)
        countdown.reminders = .arrival
        XCTAssertEqual(ReminderPlan.events(countdown: countdown, now: target.addingTimeInterval(-10 * 86400), timeZone: utc).count, 1)
    }
    func testRemindersAcrossCountdownsAreSortedAndDistinct() {
        var first = Countdown(name: "A", target: Date(timeIntervalSince1970: 2_000_000_000), timeZone: utc)
        var second = Countdown(name: "B", target: Date(timeIntervalSince1970: 1_990_000_000), timeZone: utc)
        first.reminders = .arrival; second.reminders = .milestones
        let events = ReminderPlan.events(countdowns: [first, second], now: Date(timeIntervalSince1970: 1_900_000_000), timeZone: utc)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map(\.date), events.map(\.date).sorted())
        XCTAssertEqual(Set(events.map(\.identifier)).count, 4)
    }
    func testReminderCalendarDaysAcrossDST() {
        var countdown = Countdown.gtaVI
        countdown.year = 2026; countdown.month = 3; countdown.day = 9; countdown.reminders = .milestones
        let zone = TimeZone(identifier: "America/New_York")!
        let target = countdown.targetDate(timeZone: zone)
        let events = ReminderPlan.events(countdown: countdown, now: target.addingTimeInterval(-10 * 86400), timeZone: zone)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(target.timeIntervalSince(events[1].date), 23 * 3600)
    }
    func testLiveActivityUsesOnlyFinalEightHours() {
        let target = Countdown.gtaVI.targetDate(timeZone: utc)
        XCTAssertFalse(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(-86400)))
        XCTAssertTrue(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(-8 * 3600)))
        XCTAssertTrue(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(-1)))
        XCTAssertFalse(LiveCountdownEligibility.allows(target: target, now: target))
        XCTAssertFalse(LiveCountdownEligibility.allows(target: target, now: target.addingTimeInterval(1)))
    }
    func testSpokenCountdownNeverBecomesNegative() {
        let target = Countdown.gtaVI.targetDate(timeZone: utc)
        XCTAssertEqual(Remaining(target: target, now: target).summary(name: "GTA VI"), "GTA VI: وصل الموعد")
        XCTAssertFalse(Remaining(target: target, now: target.addingTimeInterval(-90061)).summary(name: "GTA VI").contains("-"))
    }
    func testNextCountdownPrefersSoonestUpcoming() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let past = Countdown(name: "Past", target: now.addingTimeInterval(-86400))
        let later = Countdown(name: "Later", target: now.addingTimeInterval(9 * 86400))
        let soon = Countdown(name: "Soon", target: now.addingTimeInterval(2 * 86400))
        XCTAssertEqual(CountdownLookup.next(in: [past, later, soon], now: now)?.name, "Soon")
        XCTAssertEqual(CountdownLookup.next(in: [past], now: now)?.name, "Past")
        XCTAssertNil(CountdownLookup.next(in: [], now: now))
    }
    func testWidgetCanBeConfiguredWithoutTheApp() {
        var intent = SelectCountdownIntent()
        XCTAssertNil(intent.manualCountdown)
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        intent.date = date; intent.name = "  Eid  "; intent.theme = .ocean; intent.font = .didot; intent.showClock = false
        let manual = intent.manualCountdown
        XCTAssertEqual(manual?.name, "Eid")
        XCTAssertEqual(manual?.targetDate().timeIntervalSince1970 ?? 0, 2_000_000_000 - 2_000_000_000.truncatingRemainder(dividingBy: 60), accuracy: 0.5)
        XCTAssertEqual(manual?.style.accent, "#5AC8FA")
        XCTAssertEqual(manual?.style.font, .didot)
        XCTAssertEqual(manual?.style.showClock, false)
        XCTAssertTrue(manual?.isValid ?? false)
    }
    func testWidgetKeepsTheChosenCountdownWithoutTheAppData() async throws {
        var countdown = Countdown(name: "COd M4", target: Date(timeIntervalSince1970: 2_000_000_000))
        countdown.imageFilename = "photo-x.jpg"
        countdown.style = CountdownStyle(background: "#0B1E3F", text: "#E8F1FF", accent: "#5AC8FA", font: .futura)
        let entity = CountdownEntity(countdown)
        let restored = try XCTUnwrap(CountdownEntity(id: entity.id))
        var expected = countdown; expected.imageFilename = nil
        XCTAssertEqual(restored.countdown, expected)
        // Resolves from the identifier alone, as the widget does without an App Group.
        let resolved = try await CountdownQuery().entities(for: [entity.id])
        XCTAssertEqual(resolved.first?.countdown, expected)
        XCTAssertEqual(CountdownLookup.find(entity, in: []), expected)
        var live = countdown; live.name = "Renamed"
        XCTAssertEqual(CountdownLookup.find(entity, in: [live])?.name, "Renamed")
        XCTAssertNil(CountdownEntity(id: "garbage"))
    }
}
