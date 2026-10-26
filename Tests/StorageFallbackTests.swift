import XCTest
@testable import GTAVITimer

final class StorageFallbackTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testPersonalSigningKeepsCountdownsAndPhotosLocally() throws {
        let local = root.appendingPathComponent("local")
        let store = try SettingsStore.select(sharedRoot: nil, localRoot: local)
        XCTAssertEqual(store.scope, .applicationOnly)
        var countdown = Countdown(name: "Trip")
        countdown.imageFilename = try store.saveImage(Data([1, 2, 3]))
        try store.save([countdown])
        let reopened = try SettingsStore.select(sharedRoot: nil, localRoot: local)
        XCTAssertEqual(try reopened.load(), [countdown])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.imageURL(for: countdown))), Data([1, 2, 3]))
    }

    func testLaterSharedSigningMigratesOnceWithoutOverwritingSharedData() throws {
        let local = root.appendingPathComponent("local")
        let shared = root.appendingPathComponent("shared")
        let localStore = try SettingsStore.select(sharedRoot: nil, localRoot: local)
        var countdown = Countdown(name: "Exam")
        countdown.imageFilename = try localStore.saveImage(Data([4, 5, 6]))
        try localStore.save([countdown])
        var appearance = AppAppearance(); appearance.accent = "#FF0000"
        try localStore.saveAppearance(appearance)

        let upgraded = try SettingsStore.select(sharedRoot: shared, localRoot: local)
        XCTAssertEqual(upgraded.scope, .shared)
        XCTAssertEqual(try upgraded.load(), [countdown])
        XCTAssertEqual(upgraded.loadAppearance().accent, "#FF0000")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(upgraded.imageURL(for: countdown))), Data([4, 5, 6]))

        var changed = countdown; changed.name = "Exam 2"
        try upgraded.save([changed])
        let reopened = try SettingsStore.select(sharedRoot: shared, localRoot: local)
        XCTAssertEqual(try reopened.load().first?.name, "Exam 2")
    }
}
