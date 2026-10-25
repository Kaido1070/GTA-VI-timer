import XCTest
import SwiftUI
import UIKit
@testable import GTAVITimer

final class TimerTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testBeforeAtAndAfter() {
        let target = TimerSettings().targetDate(timeZone: TimeZone(secondsFromGMT: 0)!)
        let before = Remaining(target: target, now: target.addingTimeInterval(-90061))
        XCTAssertEqual(before, Remaining(target: target, now: target.addingTimeInterval(-90061)))
        XCTAssertEqual(before.days, 1); XCTAssertEqual(before.hours, 1)
        XCTAssertEqual(before.minutes, 1); XCTAssertEqual(before.seconds, 1)
        XCTAssertFalse(before.reached)
        for offset in [0.0, 1, 86400] {
            let value = Remaining(target: target, now: target.addingTimeInterval(offset))
            XCTAssertTrue(value.reached)
            XCTAssertEqual([value.days, value.hours, value.minutes, value.seconds], [0, 0, 0, 0])
        }
        XCTAssertEqual(Remaining(target: target, now: target.addingTimeInterval(-86399)).days, 0)
    }

    func testLocalMidnightAndDST() {
        var settings = TimerSettings()
        let riyadh = TimeZone(identifier: "Asia/Riyadh")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = riyadh
        let target = settings.targetDate(timeZone: riyadh)
        XCTAssertEqual(calendar.component(.hour, from: target), 0)
        XCTAssertEqual(calendar.component(.day, from: target), 19)
        XCTAssertEqual(target.timeIntervalSince(settings.targetDate(timeZone: TimeZone(secondsFromGMT: 0)!)), -10800)
        settings.year = 2026; settings.month = 3; settings.day = 9
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let remaining = Remaining(target: settings.targetDate(timeZone: calendar.timeZone), now: start)
        XCTAssertEqual(remaining.days, 0); XCTAssertEqual(remaining.hours, 23)
    }

    func testSharedSettingsAndImageRoundTrip() throws {
        let writer = SettingsStore(root: root!)
        let reader = SettingsStore(root: root!)
        XCTAssertEqual(try reader.load(), TimerSettings())
        var value = TimerSettings(); value.name = "My Game"; value.day = 20
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let saved = try writer.save(value, newJPEG: jpeg)
        XCTAssertEqual(try reader.load(), saved)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reader.imageURL(for: saved))), jpeg)
        XCTAssertNotNil(UIImage(data: jpeg))
        var reset = saved; reset.imageFilename = nil
        try writer.save(reset)
        XCTAssertNil(try reader.load().imageFilename)
        // The previous snapshot's immutable image still exists.
        XCTAssertNotNil(try reader.imageURL(for: saved))
    }

    func testFailuresDoNotReplaceSettings() throws {
        let store = SettingsStore(root: root!)
        try store.save(TimerSettings())
        var invalid = TimerSettings(); invalid.name = " "
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(), TimerSettings())
        invalid = TimerSettings(); invalid.imageFilename = "../../private.jpg"
        XCTAssertThrowsError(try store.imageURL(for: invalid))
        let file = root.appendingPathComponent("file")
        try Data([0]).write(to: file)
        XCTAssertThrowsError(try SettingsStore(root: file).save(TimerSettings(), newJPEG: Data([1])))
    }

    func testScheduleContainsDayTransitionsAndArrival() {
        let target = Date(timeIntervalSince1970: 1805500800)
        let now = target.addingTimeInterval(-90000)
        let dates = CountdownSchedule.dates(now: now, target: target)
        XCTAssertEqual(dates.first, now)
        XCTAssertTrue(dates.contains(target))
        XCTAssertTrue(dates.contains { abs($0.timeIntervalSince(target.addingTimeInterval(-86400))) < 1 })
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(CountdownSchedule.dates(now: target, target: target), [target])
    }

    @MainActor func testRenderEvidence() throws {
        let settings = TimerSettings()
        let remaining = Remaining(target: settings.targetDate(), now: settings.targetDate().addingTimeInterval(-24 * 86400))
        let cases: [(String, AnyView, CGSize)] = [
            ("Home-390", AnyView(HomeView()), CGSize(width: 390, height: 844)),
            ("Home-320", AnyView(HomeView()), CGSize(width: 320, height: 740)),
            ("Square-card", AnyView(DaysArtworkCard(settings: settings, remaining: remaining)), CGSize(width: 170, height: 170)),
            ("Lock-art-only-NOT-system-rendering", AnyView(DaysArtworkCard(settings: settings, remaining: remaining, compact: true)), CGSize(width: 64, height: 64))
        ]
        for (name, view, size) in cases {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertNotNil(UIImage(named: "Artwork"))
    }
}
