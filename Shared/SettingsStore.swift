import Foundation

struct SettingsStore {
    enum Failure: LocalizedError {
        case groupUnavailable, invalidSettings, invalidImagePath
        var errorDescription: String? {
            switch self {
            case .groupUnavailable: return "تعذّر فتح App Group. فعّل المجموعة نفسها للتطبيق والودجت في Signing & Capabilities وأعد التوقيع والتثبيت."
            case .invalidSettings: return "الاسم أو التاريخ غير صالح."
            case .invalidImagePath: return "تعذّر قراءة مسار الصورة المحفوظة."
            }
        }
    }
    enum Scope { case shared, applicationOnly }
    let root: URL
    let scope: Scope
    init(root: URL, scope: Scope = .shared) { self.root = root; self.scope = scope }

    private var listURL: URL { root.appendingPathComponent("countdowns.json") }
    private var appearanceURL: URL { root.appendingPathComponent("appearance.json") }
    /// The single-timer file written by GTA VI Timer 1.x.
    private var legacyURL: URL { root.appendingPathComponent("settings.json") }

    // Personal signing may strip / disallow App Groups. Keep app editing usable
    // without claiming that the widget can read this private container.
    static func available() throws -> SettingsStore {
        let local = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("TimerSettings", isDirectory: true)
        return try select(sharedRoot: (try? shared())?.root, localRoot: local)
    }

    static func select(sharedRoot: URL?, localRoot: URL) throws -> SettingsStore {
        let local = SettingsStore(root: localRoot, scope: .applicationOnly)
        guard let sharedRoot else { return local }
        let store = SettingsStore(root: sharedRoot)
        // Migrate only into an empty shared store after a later signing upgrade.
        if !store.hasData, local.hasData {
            var images: [String: Data] = [:]
            let list = try local.load()
            for countdown in list {
                if let url = try local.imageURL(for: countdown) { images[countdown.imageFilename!] = try Data(contentsOf: url) }
            }
            try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
            for (name, data) in images { try data.write(to: sharedRoot.appendingPathComponent(name), options: .atomic) }
            try store.save(list)
            try store.saveAppearance(local.loadAppearance())
        }
        return store
    }

    static func shared() throws -> SettingsStore {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw Failure.groupUnavailable
        }
        return SettingsStore(root: root)
    }

    var hasData: Bool {
        FileManager.default.fileExists(atPath: listURL.path) || FileManager.default.fileExists(atPath: legacyURL.path)
    }

    /// All countdowns in the user's order. A 1.x settings file becomes the first one.
    func load() throws -> [Countdown] {
        if FileManager.default.fileExists(atPath: listURL.path) {
            let list = try JSONDecoder().decode([Countdown].self, from: Data(contentsOf: listURL))
            guard list.allSatisfy(\.isValid) else { throw Failure.invalidSettings }
            return list
        }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return [] }
        var legacy = try JSONDecoder().decode(Countdown.self, from: Data(contentsOf: legacyURL))
        guard legacy.isValid else { throw Failure.invalidSettings }
        // 1.x showed the bundled artwork whenever no photo was chosen.
        legacy.builtinArtwork = legacy.imageFilename == nil
        legacy.style = Countdown.gtaVI.style
        return [legacy]
    }

    /// First launch of the app: start with the original countdown so nothing is lost.
    func seedIfEmpty() throws -> [Countdown] {
        let list = try load()
        if !FileManager.default.fileExists(atPath: listURL.path) {
            let seeded = list.isEmpty ? [Countdown.gtaVI] : list
            try save(seeded)
            return seeded
        }
        return list
    }

    func imageURL(for countdown: Countdown) throws -> URL? {
        guard let filename = countdown.imageFilename else { return nil }
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.hasPrefix("photo-"), filename.hasSuffix(".jpg") else { throw Failure.invalidImagePath }
        return root.appendingPathComponent(filename)
    }

    /// Images are immutable; a new photo always gets a new name and is written
    /// before the list that references it.
    func saveImage(_ jpeg: Data) throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let filename = "photo-\(UUID().uuidString).jpg"
        try jpeg.write(to: root.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func save(_ list: [Countdown]) throws {
        guard list.allSatisfy(\.isValid) else { throw Failure.invalidSettings }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: listURL, options: .atomic)
        removeUnusedImages(keeping: Set(list.compactMap(\.imageFilename)))
    }

    /// Inserts or replaces one countdown, keeping the others untouched.
    @discardableResult
    func upsert(_ countdown: Countdown) throws -> [Countdown] {
        var list = try load()
        if let index = list.firstIndex(where: { $0.id == countdown.id }) { list[index] = countdown } else { list.append(countdown) }
        try save(list)
        return list
    }

    func loadAppearance() -> AppAppearance {
        (try? JSONDecoder().decode(AppAppearance.self, from: Data(contentsOf: appearanceURL))) ?? AppAppearance()
    }

    func saveAppearance(_ value: AppAppearance) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: appearanceURL, options: .atomic)
    }

    private func removeUnusedImages(keeping used: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in files where name.hasPrefix("photo-") && name.hasSuffix(".jpg") && !used.contains(name) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }
}
