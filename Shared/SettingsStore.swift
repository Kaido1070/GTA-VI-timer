import Foundation

struct SettingsStore {
    enum Failure: LocalizedError {
        case groupUnavailable, invalidSettings, invalidImagePath
        var errorDescription: String? {
            switch self {
            case .groupUnavailable: return "تعذّر فتح App Group. فعّل المجموعة نفسها للتطبيق والودجت في Signing & Capabilities وأعد التوقيع والتثبيت. لم تُحفظ التغييرات."
            case .invalidSettings: return "الاسم أو التاريخ غير صالح."
            case .invalidImagePath: return "تعذّر قراءة مسار الصورة المحفوظة."
            }
        }
    }
    enum Scope { case shared, applicationOnly }
    let root: URL
    let scope: Scope
    init(root: URL, scope: Scope = .shared) { self.root = root; self.scope = scope }

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
        if !FileManager.default.fileExists(atPath: sharedRoot.appendingPathComponent("settings.json").path),
           FileManager.default.fileExists(atPath: localRoot.appendingPathComponent("settings.json").path) {
            let settings = try local.load()
            let jpeg = try local.imageURL(for: settings).map { try Data(contentsOf: $0) }
            try store.save(settings, newJPEG: jpeg)
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

    func load() throws -> TimerSettings {
        let path = root.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return TimerSettings() }
        let value = try JSONDecoder().decode(TimerSettings.self, from: Data(contentsOf: path))
        guard value.isValid else { throw Failure.invalidSettings }
        return value
    }

    func imageURL(for settings: TimerSettings) throws -> URL? {
        guard let filename = settings.imageFilename else { return nil }
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.hasPrefix("photo-"), filename.hasSuffix(".jpg") else { throw Failure.invalidImagePath }
        return root.appendingPathComponent(filename)
    }

    // A new immutable image is committed before the atomic settings pointer.
    // Old images remain valid for widget snapshots and concurrent readers.
    @discardableResult
    func save(_ settings: TimerSettings, newJPEG: Data? = nil) throws -> TimerSettings {
        guard settings.isValid else { throw Failure.invalidSettings }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var next = settings
        var created: URL?
        if let data = newJPEG {
            let filename = "photo-\(UUID().uuidString).jpg"
            let url = root.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            created = url
            next.imageFilename = filename
        }
        do {
            try JSONEncoder().encode(next).write(to: root.appendingPathComponent("settings.json"), options: .atomic)
        } catch {
            if let created { try? FileManager.default.removeItem(at: created) }
            throw error
        }
        return next
    }
}
