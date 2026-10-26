import ActivityKit
import Foundation

struct LiveCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var target: Date
        var startedAt: Date
    }
    var name: String
    var countdownID: String = ""
    var accent: String = "#D6A84E"
}

enum LiveCountdownEligibility {
    // ActivityKit ends an activity after at most 8 hours. A month-long
    // countdown stays in normal widgets; the live surface is for the finale.
    static let maximumDuration: TimeInterval = 8 * 3600
    static func allows(target: Date, now: Date) -> Bool {
        let duration = target.timeIntervalSince(now)
        return duration > 0 && duration <= maximumDuration
    }
}
