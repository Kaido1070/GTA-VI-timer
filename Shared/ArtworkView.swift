import SwiftUI
import UIKit
import ImageIO
import WidgetKit

private enum ArtworkLoader {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 12 * 1024 * 1024
        cache.countLimit = 4
        return cache
    }()
    static func load(settings: TimerSettings, maximumPixelSize: Int) -> UIImage? {
        var url = Bundle.main.url(forResource: "Artwork", withExtension: "jpg")
        if settings.imageFilename != nil,
           let store = try? SettingsStore.available(),
           let saved = try? store.imageURL(for: settings),
           FileManager.default.fileExists(atPath: saved.path) { url = saved }
        guard let url else { return UIImage(named: "Artwork") }
        let key = "\(url.path)-\(maximumPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return UIImage(named: "Artwork") }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}

struct ArtworkView: View {
    let settings: TimerSettings
    var maximumPixelSize = 1200
    var blurredFill = true
    var body: some View {
        GeometryReader { geometry in
            let artwork = ArtworkLoader.load(settings: settings, maximumPixelSize: maximumPixelSize)
                .map { Image(uiImage: $0) } ?? Image("Artwork")
            ZStack {
                Color.black
                if blurredFill { artwork.resizable().scaledToFill().blur(radius: 18).opacity(0.6) }
                artwork.resizable().scaledToFit()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

struct DaysArtworkCard: View {
    let settings: TimerSettings
    let remaining: Remaining
    var compact = false
    var body: some View {
        ZStack(alignment: .bottom) {
            // Decode only a thumbnail and avoid a second blurred surface in the
            // memory-constrained widget extension. Keep the original file intact.
            ArtworkView(settings: settings, maximumPixelSize: compact ? 240 : 600, blurredFill: false)
            VStack(spacing: 0) {
                if remaining.reached {
                    Text("وصل الموعد").font(.headline)
                } else {
                    Text("\(remaining.days)").font(.system(size: compact ? 26 : 48, weight: .heavy, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                    Text("يوم").font(compact ? .caption2 : .headline)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 2)
            .padding(compact ? 3 : 10)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .padding(compact ? 2 : 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.reached ? "وصل الموعد" : "\(settings.name)، \(remaining.days) يوم متبقٍ")
    }
}

// Lock-screen accessoryRectangular content: the artwork as a full-height square
// tile plus English text (days and a live h:mm:ss) filling the rest. Fixed point sizes
// keep the layout stable. The system renders the lock screen vibrantly, so the
// artwork appears as a tinted, semi-transparent image there.
struct LockRectangularView: View {
    let settings: TimerSettings
    let remaining: Remaining
    var now = Date()
    var storageError = false
    private var dayBoundary: Date {
        max(now, settings.targetDate().addingTimeInterval(-Double(remaining.days) * 86_400))
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                ArtworkView(settings: settings, maximumPixelSize: 240, blurredFill: false)
                    .frame(width: geometry.size.height, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 0) {
                    Text(settings.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if remaining.reached {
                        Text("OUT NOW")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            // Scale factors don't shrink reliably inside this row; size by digit count.
                            Text(verbatim: String(remaining.days))
                                .font(.system(size: remaining.days >= 1000 ? 20 : 28, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .widgetAccentable()
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Text(remaining.days == 1 ? "DAY" : "DAYS").font(.system(size: 13, weight: .bold))
                                .lineLimit(1).fixedSize()
                        }
                        // Hours:minutes:seconds left in the current day, ticking live.
                        // The timeline reloads at each day boundary to roll the day count.
                        Text(timerInterval: now...dayBoundary, countsDown: true)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if storageError {
                        Text("Settings unreadable").font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.reached ? "\(settings.name), out now" : "\(settings.name), \(remaining.days) days left")
    }
}
