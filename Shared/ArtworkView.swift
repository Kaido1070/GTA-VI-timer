import SwiftUI
import UIKit
import ImageIO
import WidgetKit

enum ArtworkLoader {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 12 * 1024 * 1024
        cache.countLimit = 6
        return cache
    }()

    /// The countdown's photo, the bundled artwork, or nil for colour only.
    static func load(_ countdown: Countdown, maximumPixelSize: Int) -> UIImage? {
        var url: URL?
        if countdown.imageFilename != nil,
           let store = try? SettingsStore.available(),
           let saved = try? store.imageURL(for: countdown),
           FileManager.default.fileExists(atPath: saved.path) { url = saved }
        else if countdown.builtinArtwork { url = Bundle.main.url(forResource: "Artwork", withExtension: "jpg") }
        guard let url else { return nil }
        let key = "\(url.path)-\(maximumPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        // Decode only a thumbnail; the widget extension is memory-constrained.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}

/// An image that fills its frame, cropping as needed.
struct FillImage: View {
    let image: UIImage
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// Background colour, with the photo full-bleed and dimmed when the style asks for it.
struct CountdownBackdrop: View {
    let countdown: Countdown
    let image: UIImage?
    var forceImage = false
    var body: some View {
        ZStack {
            countdown.style.backgroundColor
            if let image, forceImage || countdown.style.imageMode == .background {
                FillImage(image: image)
                Color.black.opacity(countdown.style.imageDim)
            }
        }
    }
}

/// Days plus a live h:mm:ss, in the countdown's font and colours.
struct CountdownNumbers: View {
    let countdown: Countdown
    let now: Date
    var daySize: CGFloat = 40
    var clockSize: CGFloat = 22
    var showClock: Bool? = nil
    var body: some View {
        let style = countdown.style
        let target = countdown.targetDate()
        let remaining = Remaining(target: target, now: now)
        VStack(alignment: style.alignment.horizontal, spacing: 0) {
            if remaining.reached {
                Text("NOW")
                    .font(style.font.font(daySize * 0.8))
                    .foregroundStyle(style.accentColor)
                    .lineLimit(1).minimumScaleFactor(0.5)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: String(remaining.days))
                        .font(style.font.font(remaining.days >= 1000 ? daySize * 0.7 : daySize))
                        .foregroundStyle(style.accentColor)
                        .widgetAccentable()
                    Text(remaining.days == 1 ? "DAY" : "DAYS")
                        .font(style.font.font(max(11, daySize * 0.32)))
                        .foregroundStyle(style.textColor)
                        .fixedSize()
                }
                .lineLimit(1)
                if showClock ?? style.showClock {
                    // The system ticks this text; the timeline reloads at each
                    // day boundary to roll the day count.
                    Text(timerInterval: now...Remaining.dayBoundary(target: target, now: now), countsDown: true)
                        .font(style.font.font(clockSize))
                        .foregroundStyle(style.textColor)
                        .monospacedDigit()
                        .multilineTextAlignment(style.alignment.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
    }
}

struct CountdownTitle: View {
    let countdown: Countdown
    var nameSize: CGFloat = 17
    var body: some View {
        let style = countdown.style
        VStack(alignment: style.alignment.horizontal, spacing: 1) {
            if style.showName {
                Text(countdown.name).font(style.font.font(nameSize))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            if style.showDate {
                Text(countdown.targetDate(), format: dateFormat)
                    .font(.system(size: max(11, nameSize * 0.7), weight: .medium))
                    .opacity(0.75)
                    .environment(\.locale, Locale(identifier: "en_US"))
            }
        }
        .foregroundStyle(style.textColor)
    }
    private var dateFormat: Date.FormatStyle {
        countdown.hour == 0 && countdown.minute == 0
            ? .dateTime.day().month(.abbreviated).year()
            : .dateTime.day().month(.abbreviated).year().hour().minute()
    }
}

private struct ImageTile: View {
    let image: UIImage
    var radius: CGFloat = 16
    var body: some View {
        FillImage(image: image)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }
}

// MARK: - Home-screen widgets

/// Small, medium and large widgets. Layout follows the countdown's style.
struct HomeCountdownView: View {
    let countdown: Countdown
    var now = Date()
    var family: WidgetFamily = .systemMedium
    var storageError = false

    var body: some View {
        let image = ArtworkLoader.load(countdown, maximumPixelSize: family == .systemLarge ? 700 : 420)
        let style = countdown.style
        let tile = style.imageMode == .tile ? image : nil
        ZStack {
            CountdownBackdrop(countdown: countdown, image: image)
            switch family {
            case .systemSmall:
                VStack(alignment: style.alignment.horizontal, spacing: 4) {
                    CountdownTitle(countdown: countdown, nameSize: 15)
                    Spacer(minLength: 0)
                    CountdownNumbers(countdown: countdown, now: now, daySize: 38, clockSize: 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.frame)
                .padding(14)
                .background(alignment: .topTrailing) {
                    if let tile, style.alignment != .trailing {
                        ImageTile(image: tile, radius: 12).frame(width: 52, height: 52).padding(12)
                    }
                }
            case .systemLarge:
                VStack(spacing: 14) {
                    if let tile {
                        FillImage(image: tile)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                    } else {
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: style.alignment.horizontal, spacing: 8) {
                        CountdownTitle(countdown: countdown, nameSize: 22)
                        CountdownNumbers(countdown: countdown, now: now,
                                         daySize: tile == nil ? 72 : 44, clockSize: tile == nil ? 34 : 24)
                    }
                    .frame(maxWidth: .infinity, alignment: style.alignment.frame)
                    if tile == nil { Spacer(minLength: 0) }
                }
                .padding(16)
            default:
                HStack(spacing: 14) {
                    VStack(alignment: style.alignment.horizontal, spacing: 2) {
                        CountdownTitle(countdown: countdown)
                        Spacer(minLength: 4)
                        CountdownNumbers(countdown: countdown, now: now,
                                         daySize: tile == nil ? 48 : 40, clockSize: tile == nil ? 26 : 22)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.frame)
                    if let tile { ImageTile(image: tile) }
                }
                .padding(14)
            }
            if storageError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(countdown, now: now))
    }
}

/// Shown when the widget can't see any countdown (none yet, or no App Group).
struct EmptyCountdownView: View {
    var compact = false
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hourglass").font(.system(size: compact ? 18 : 28, weight: .semibold))
                .foregroundStyle(Color(hex: "#D6A84E"))
            if !compact {
                Text("AnyTimer").font(.system(size: 15, weight: .bold))
                Text("Open the app to add a countdown").font(.system(size: 11)).opacity(0.7)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Lock screen

// accessoryRectangular: the image as a full-height square tile (unless hidden)
// plus text filling the rest. The system renders the lock screen vibrantly,
// so colours become a single tint there.
struct LockRectangularView: View {
    let countdown: Countdown
    var now = Date()
    var storageError = false
    var body: some View {
        let image = countdown.style.imageMode == .hidden ? nil : ArtworkLoader.load(countdown, maximumPixelSize: 240)
        GeometryReader { geometry in
            HStack(spacing: 8) {
                if let image {
                    FillImage(image: image)
                        .frame(width: geometry.size.height, height: geometry.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(countdown.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    CountdownNumbers(countdown: lockStyled, now: now, daySize: 28, clockSize: 15, showClock: true)
                    if storageError {
                        Text("Settings unreadable").font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(countdown, now: now))
    }
    /// Keep the font, but let the system tint everything on the lock screen.
    private var lockStyled: Countdown {
        var value = countdown
        value.style.text = "#FFFFFF"; value.style.accent = "#FFFFFF"; value.style.alignment = .leading
        return value
    }
}

private func accessibility(_ countdown: Countdown, now: Date) -> String {
    let remaining = Remaining(target: countdown.targetDate(), now: now)
    return remaining.reached ? "\(countdown.name), now" : "\(countdown.name), \(remaining.days) days left"
}

// MARK: - App

/// A countdown card for the app's list, ticking each second while visible.
struct CountdownCard: View {
    let countdown: Countdown
    let now: Date
    var height: CGFloat = 190
    /// A photo picked in the editor but not saved yet.
    var imageOverride: UIImage?
    var body: some View {
        let image = imageOverride ?? ArtworkLoader.load(countdown, maximumPixelSize: 900)
        let style = countdown.style
        ZStack {
            CountdownBackdrop(countdown: countdown, image: image, forceImage: style.imageMode != .hidden)
            LinearGradient(colors: [.clear, .black.opacity(image == nil || style.imageMode == .hidden ? 0 : 0.45)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: style.alignment.horizontal, spacing: 6) {
                CountdownTitle(countdown: countdown, nameSize: height > 150 ? 22 : 17)
                Spacer(minLength: 0)
                CountdownNumbers(countdown: countdown, now: now,
                                 daySize: height > 150 ? 46 : 32, clockSize: height > 150 ? 22 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.frame)
            .padding(16)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(countdown, now: now))
    }
}
