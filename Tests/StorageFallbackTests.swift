import XCTest
@testable import GTAVITimer

final class StorageFallbackTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testPersonalSigningKeepsAppSettingsAndPhotoLocally() throws {
        let local = root.appendingPathComponent("local")
        let store = try SettingsStore.select(sharedRoot: nil, localRoot: local)
        XCTAssertEqual(store.scope, .applicationOnly)
        var settings = TimerSettings(); settings.name = "Personal Game"
        let saved = try store.save(settings, newJPEG: Data([1, 2, 3]))
        let reopened = try SettingsStore.select(sharedRoot: nil, localRoot: local)
        XCTAssertEqual(try reopened.load(), saved)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.imageURL(for: saved))), Data([1, 2, 3]))
    }
    func testLaterSharedSigningMigratesOnceWithoutOverwritingSharedSettings() throws {
        let local = root.appendingPathComponent("local")
        let shared = root.appendingPathComponent("shared")
        let localStore = try SettingsStore.select(sharedRoot: nil, localRoot: local)
        var settings = TimerSettings(); settings.day = 20
        try localStore.save(settings, newJPEG: Data([4, 5, 6]))
        let upgraded = try SettingsStore.select(sharedRoot: shared, localRoot: local)
        XCTAssertEqual(upgraded.scope, .shared)
        XCTAssertEqual(try upgraded.load().day, 20)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(upgraded.imageURL(for: upgraded.load()))), Data([4, 5, 6]))
        var sharedSettings = try upgraded.load(); sharedSettings.day = 21
        try upgraded.save(sharedSettings)
        let reopened = try SettingsStore.select(sharedRoot: shared, localRoot: local)
        XCTAssertEqual(try reopened.load().day, 21)
    }
}
