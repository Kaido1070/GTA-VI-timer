import Foundation
import SwiftUI
import UIKit

// One user-defined countdown. Persist a civil date and wall-clock time, never
// an absolute UTC timestamp, so it is re-evaluated in the device's current
// timezone, including after travel / a timezone change.
struct Countdown: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "New Countdown"
    var year = 2026
    var month = 1
    var day = 1
    var hour = 0
    var minute = 0
    /// A photo saved in the store (`photo-<uuid>.jpg`).
    var imageFilename: String?
    /// The artwork bundled with the app (kept for the original GTA VI countdown).
    var builtinArtwork = false
    var style = CountdownStyle()
    var reminders: ReminderMode?
    var reminderMode: ReminderMode { reminders ?? .off }

    init(id: UUID = UUID(), name: String = "New Countdown", target: Date = .now.addingTimeInterval(30 * 86_400),
         timeZone: TimeZone = .current) {
        self.id = id
        self.name = name
        setTarget(target, timeZone: timeZone)
    }

    func targetDate(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    mutating func setTarget(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!; hour = parts.hour!; minute = parts.minute!
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: targetDate())
        return parts.year == year && parts.month == month && parts.day == day
    }

    // Older files and the original single-timer settings lack the newer keys.
    enum CodingKeys: String, CodingKey {
        case id, name, year, month, day, hour, minute, imageFilename, builtinArtwork, style, reminders
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        year = try c.decode(Int.self, forKey: .year)
        month = try c.decode(Int.self, forKey: .month)
        day = try c.decode(Int.self, forKey: .day)
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 0
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        imageFilename = try c.decodeIfPresent(String.self, forKey: .imageFilename)
        builtinArtwork = try c.decodeIfPresent(Bool.self, forKey: .builtinArtwork) ?? false
        style = try c.decodeIfPresent(CountdownStyle.self, forKey: .style) ?? CountdownStyle()
        reminders = try c.decodeIfPresent(ReminderMode.self, forKey: .reminders)
    }

    /// The countdown every install of the original GTA VI Timer started with.
    static var gtaVI: Countdown {
        var value = Countdown(name: "GTA VI")
        value.year = 2026; value.month = 11; value.day = 19; value.hour = 0; value.minute = 0
        value.builtinArtwork = true
        value.style = CountdownStyle(background: "#1B1036", text: "#FFFFFF", accent: "#FF9EC7", font: .rounded,
                                     imageDim: 0.2, imageMode: .tile)
        return value
    }
}

struct CountdownStyle: Codable, Equatable {
    var background = "#14161F"
    var text = "#FFFFFF"
    var accent = "#D6A84E"
    var font = FontChoice.rounded
    /// Darkening over a photo so text stays readable, 0...0.8.
    var imageDim = 0.35
    // Widget layout, chosen per countdown.
    var imageMode = ImageMode.tile
    var alignment = TextAlignmentChoice.leading
    var showName = true
    var showDate = true
    var showClock = true

    var backgroundColor: Color { Color(hex: background) }
    var textColor: Color { Color(hex: text) }
    var accentColor: Color { Color(hex: accent) }

    init(background: String = "#14161F", text: String = "#FFFFFF", accent: String = "#D6A84E",
         font: FontChoice = .rounded, imageDim: Double = 0.35, imageMode: ImageMode = .tile) {
        self.background = background; self.text = text; self.accent = accent; self.font = font
        self.imageDim = imageDim; self.imageMode = imageMode
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CountdownStyle()
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? fallback.background
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? fallback.text
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? fallback.accent
        font = (try? c.decodeIfPresent(FontChoice.self, forKey: .font)) ?? fallback.font
        imageDim = try c.decodeIfPresent(Double.self, forKey: .imageDim) ?? fallback.imageDim
        imageMode = (try? c.decodeIfPresent(ImageMode.self, forKey: .imageMode)) ?? fallback.imageMode
        alignment = (try? c.decodeIfPresent(TextAlignmentChoice.self, forKey: .alignment)) ?? fallback.alignment
        showName = try c.decodeIfPresent(Bool.self, forKey: .showName) ?? true
        showDate = try c.decodeIfPresent(Bool.self, forKey: .showDate) ?? true
        showClock = try c.decodeIfPresent(Bool.self, forKey: .showClock) ?? true
    }
}

enum ImageMode: String, Codable, CaseIterable, Identifiable {
    case tile, background, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tile: return "بجانب النص"
        case .background: return "خلفية كاملة"
        case .hidden: return "بدون صورة"
        }
    }
}

enum TextAlignmentChoice: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leading: return "يسار"
        case .center: return "وسط"
        case .trailing: return "يمين"
        }
    }
    var horizontal: HorizontalAlignment { self == .leading ? .leading : self == .center ? .center : .trailing }
    var frame: Alignment { self == .leading ? .leading : self == .center ? .center : .trailing }
    var text: TextAlignment { self == .leading ? .leading : self == .center ? .center : .trailing }
}

/// App-wide look, separate from each countdown's own style.
struct AppAppearance: Codable, Equatable {
    var accent = "#D6A84E"
    var background = "#000000"
    var cardSize = CardSize.large
    enum CardSize: String, Codable, CaseIterable, Identifiable {
        case compact, large
        var id: String { rawValue }
        var title: String { self == .compact ? "مضغوطة" : "كبيرة" }
        var height: CGFloat { self == .compact ? 120 : 190 }
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "#D6A84E"
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? "#000000"
        cardSize = (try? c.decodeIfPresent(CardSize.self, forKey: .cardSize)) ?? .large
    }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    case avenir, futura, didot, bodoni, baskerville, georgia, optima, gillSans
    case copperplate, americanTypewriter, snellRoundhand, markerFelt, chalkboard, noteworthy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .avenir: return "Avenir Next"
        case .futura: return "Futura"
        case .didot: return "Didot"
        case .bodoni: return "Bodoni"
        case .baskerville: return "Baskerville"
        case .georgia: return "Georgia"
        case .optima: return "Optima"
        case .gillSans: return "Gill Sans"
        case .copperplate: return "Copperplate"
        case .americanTypewriter: return "Typewriter"
        case .snellRoundhand: return "Snell Roundhand"
        case .markerFelt: return "Marker Felt"
        case .chalkboard: return "Chalkboard"
        case .noteworthy: return "Noteworthy"
        }
    }
    private var postScriptName: String? {
        switch self {
        case .system, .rounded, .serif, .mono: return nil
        case .avenir: return "AvenirNext-Bold"
        case .futura: return "Futura-Bold"
        case .didot: return "Didot-Bold"
        case .bodoni: return "BodoniSvtyTwoITCTT-Bold"
        case .baskerville: return "Baskerville-Bold"
        case .georgia: return "Georgia-Bold"
        case .optima: return "Optima-Bold"
        case .gillSans: return "GillSans-Bold"
        case .copperplate: return "Copperplate-Bold"
        case .americanTypewriter: return "AmericanTypewriter-Bold"
        case .snellRoundhand: return "SnellRoundhand-Bold"
        case .markerFelt: return "MarkerFelt-Wide"
        case .chalkboard: return "ChalkboardSE-Bold"
        case .noteworthy: return "Noteworthy-Bold"
        }
    }
    /// A fixed-size bold face; widgets and cards size their own text.
    func font(_ size: CGFloat) -> Font {
        switch self {
        case .system: return .system(size: size, weight: .bold)
        case .rounded: return .system(size: size, weight: .heavy, design: .rounded)
        case .serif: return .system(size: size, weight: .bold, design: .serif)
        case .mono: return .system(size: size, weight: .bold, design: .monospaced)
        default: return .custom(postScriptName!, fixedSize: size)
        }
    }
}

extension Color {
    /// `#RRGGBB`; anything unreadable falls back to white.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { self = .white; return }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

struct Remaining: Equatable {
    let reached: Bool
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    init(target: Date, now: Date) {
        let interval = target.timeIntervalSince(now)
        reached = interval <= 0
        let total = Int(max(0, interval.rounded(.down)))
        days = total / 86_400
        hours = (total % 86_400) / 3_600
        minutes = (total % 3_600) / 60
        seconds = total % 60
    }

    func summary(name: String) -> String {
        reached ? "\(name): وصل الموعد" : "\(name): باقي \(days) يوم و\(hours) ساعة و\(minutes) دقيقة و\(seconds) ثانية."
    }

    /// When the whole-day count next drops; a live h:mm:ss counts down to it.
    static func dayBoundary(target: Date, now: Date) -> Date {
        let days = Remaining(target: target, now: now).days
        return max(now, target.addingTimeInterval(-Double(days) * 86_400))
    }
}

// Updates at full-day countdown boundaries, with hourly timezone refresh
// opportunities. WidgetKit controls delivery; these are requests, not guarantees.
enum CountdownSchedule {
    static func dates(now: Date, target: Date) -> [Date] {
        guard target > now else { return [now] }
        let horizon = min(target, now.addingTimeInterval(3 * 86_400))
        var dates = [now]
        var hour = now.addingTimeInterval(3_600)
        while hour <= horizon { dates.append(hour); hour.addTimeInterval(3_600) }
        let days = Int(target.timeIntervalSince(now) / 86_400)
        var boundary = target.addingTimeInterval(-Double(days) * 86_400 + 0.05)
        while boundary <= horizon {
            if boundary > now { dates.append(boundary) }
            boundary.addTimeInterval(86_400)
        }
        if target <= horizon { dates.append(target) }
        return Array(Set(dates)).sorted()
    }
}
