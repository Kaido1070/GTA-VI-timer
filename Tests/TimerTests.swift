import XCTest
import SwiftUI
import UIKit
import WidgetKit
@testable import GTAVITimer

final class TimerTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testBeforeAtAndAfter() {
        let target = Countdown.gtaVI.targetDate(timeZone: TimeZone(secondsFromGMT: 0)!)
        let before = Remaining(target: target, now: target.addingTimeInterval(-90061))
        XCTAssertEqual(before.days, 1); XCTAssertEqual(before.hours, 1)
        XCTAssertEqual(before.minutes, 1); XCTAssertEqual(before.seconds, 1)
        XCTAssertFalse(before.reached)
        for offset in [0.0, 1, 86400] {
            let value = Remaining(target: target, now: target.addingTimeInterval(offset))
            XCTAssertTrue(value.reached)
            XCTAssertEqual([value.days, value.hours, value.minutes, value.seconds], [0, 0, 0, 0])
        }
        XCTAssertEqual(Remaining(target: target, now: target.addingTimeInterval(-86399)).days, 0)
        XCTAssertEqual(Remaining.dayBoundary(target: target, now: target.addingTimeInterval(-90061)),
                       target.addingTimeInterval(-86400))
    }

    func testLocalTimeAndDST() {
        var countdown = Countdown.gtaVI
        let riyadh = TimeZone(identifier: "Asia/Riyadh")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = riyadh
        countdown.hour = 18; countdown.minute = 30
        let target = countdown.targetDate(timeZone: riyadh)
        XCTAssertEqual(calendar.component(.hour, from: target), 18)
        XCTAssertEqual(calendar.component(.minute, from: target), 30)
        XCTAssertEqual(calendar.component(.day, from: target), 19)
        var roundTrip = Countdown(name: "X", target: target, timeZone: riyadh)
        XCTAssertEqual([roundTrip.year, roundTrip.month, roundTrip.day, roundTrip.hour, roundTrip.minute], [2026, 11, 19, 18, 30])
        roundTrip.year = 2026; roundTrip.month = 3; roundTrip.day = 9; roundTrip.hour = 0; roundTrip.minute = 0
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let remaining = Remaining(target: roundTrip.targetDate(timeZone: calendar.timeZone), now: start)
        XCTAssertEqual(remaining.days, 0); XCTAssertEqual(remaining.hours, 23)
    }

    func testListAndImagesRoundTrip() throws {
        let writer = SettingsStore(root: root!)
        let reader = SettingsStore(root: root!)
        XCTAssertEqual(try reader.load(), [])
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        var first = Countdown(name: "Wedding")
        first.imageFilename = try writer.saveImage(jpeg)
        first.style = CountdownStyle(background: "#112233", text: "#FFEEDD", accent: "#AABBCC", font: .didot, imageDim: 0.5, imageMode: .background)
        first.style.alignment = .center; first.style.showClock = false
        let second = Countdown(name: "Holiday")
        try writer.save([first, second])
        XCTAssertEqual(try reader.load(), [first, second])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reader.imageURL(for: first))), jpeg)

        // Replacing a countdown's photo removes the file nobody uses any more.
        let oldURL = try XCTUnwrap(reader.imageURL(for: first))
        var replaced = first; replaced.imageFilename = try writer.saveImage(Data([9]))
        try writer.upsert(replaced)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try reader.load().map(\.name), ["Wedding", "Holiday"])
        var appearance = AppAppearance(); appearance.cardSize = .compact
        try writer.saveAppearance(appearance)
        XCTAssertEqual(reader.loadAppearance(), appearance)
    }

    func testVersionOneSettingsBecomeFirstCountdown() throws {
        try Data(#"{"name":"My Game","year":2027,"month":2,"day":3}"#.utf8).write(to: root.appendingPathComponent("settings.json"))
        let store = SettingsStore(root: root!)
        let list = try store.seedIfEmpty()
        XCTAssertEqual(list.map(\.name), ["My Game"])
        XCTAssertTrue(list[0].builtinArtwork)
        XCTAssertEqual(try store.load(), list)
        let fresh = SettingsStore(root: root.appendingPathComponent("fresh"))
        XCTAssertEqual(try fresh.seedIfEmpty().map(\.name), ["GTA VI"])
        try fresh.save([])
        XCTAssertEqual(try fresh.seedIfEmpty(), [])
    }

    func testFailuresDoNotReplaceData() throws {
        let store = SettingsStore(root: root!)
        try store.save([Countdown.gtaVI])
        var invalid = Countdown.gtaVI; invalid.name = " "
        XCTAssertThrowsError(try store.save([invalid]))
        XCTAssertEqual(try store.load().map(\.name), ["GTA VI"])
        invalid = Countdown.gtaVI; invalid.imageFilename = "../../private.jpg"
        XCTAssertThrowsError(try store.imageURL(for: invalid))
        let file = root.appendingPathComponent("file")
        try Data([0]).write(to: file)
        XCTAssertThrowsError(try SettingsStore(root: file).saveImage(Data([1])))
    }

    func testColorHexRoundTrip() {
        XCTAssertEqual(Color(hex: "#D6A84E").hex, "#D6A84E")
        XCTAssertEqual(Color(hex: "garbage").hex, "#FFFFFF")
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

    @MainActor func testRenderEvidence() async throws {
        let gta = Countdown.gtaVI
        var plain = Countdown(name: "Summer Trip", target: .now.addingTimeInterval(40 * 86400 + 5000))
        plain.style = CountdownStyle(background: "#0B1E3F", text: "#E8F1FF", accent: "#5AC8FA", font: .didot)
        var centered = Countdown(name: "Graduation", target: .now.addingTimeInterval(1200 * 86400))
        centered.style = CountdownStyle(background: "#F5F0E6", text: "#1C1C1E", accent: "#B8860B", font: .futura)
        centered.style.alignment = .center
        var backdrop = gta; backdrop.style.imageMode = .background; backdrop.style.imageDim = 0.45; backdrop.style.font = .avenir
        let cases: [(String, AnyView, CGSize)] = [
            ("Home-390", AnyView(HomeView()), CGSize(width: 390, height: 844)),
            ("Editor-390", AnyView(CountdownEditor(initial: gta, isNew: false) { _ in }), CGSize(width: 390, height: 1900)),
            ("Settings-390", AnyView(AppSettingsView(appearance: .constant(AppAppearance()), countdowns: [gta])), CGSize(width: 390, height: 900)),
            ("Widget-medium-tile", AnyView(HomeCountdownView(countdown: gta, family: .systemMedium)), CGSize(width: 338, height: 158)),
            ("Widget-medium-plain", AnyView(HomeCountdownView(countdown: plain, family: .systemMedium)), CGSize(width: 338, height: 158)),
            ("Widget-medium-backdrop", AnyView(HomeCountdownView(countdown: backdrop, family: .systemMedium)), CGSize(width: 338, height: 158)),
            ("Widget-small", AnyView(HomeCountdownView(countdown: gta, family: .systemSmall)), CGSize(width: 158, height: 158)),
            ("Widget-small-centered", AnyView(HomeCountdownView(countdown: centered, family: .systemSmall)), CGSize(width: 158, height: 158)),
            ("Widget-large", AnyView(HomeCountdownView(countdown: gta, family: .systemLarge)), CGSize(width: 338, height: 354)),
            ("Widget-large-plain", AnyView(HomeCountdownView(countdown: centered, family: .systemLarge)), CGSize(width: 338, height: 354)),
            ("Widget-empty", AnyView(EmptyCountdownView().background(Color.black)), CGSize(width: 338, height: 158)),
            // Layout check only; the system applies vibrant rendering on the lock screen.
            ("Lock-rect-170", AnyView(LockRectangularView(countdown: gta).background(Color.indigo)), CGSize(width: 170, height: 76)),
            ("Lock-rect-158", AnyView(LockRectangularView(countdown: centered).background(Color.indigo)), CGSize(width: 158, height: 72)),
        ]
        for (name, view, size) in cases {
            let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
            if name.hasPrefix("Lock-") || name.hasPrefix("Widget-") { controller.safeAreaRegions = [] }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            window.isHidden = true
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertNotNil(UIImage(named: "Artwork"))
    }
}
