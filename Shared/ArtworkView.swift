import SwiftUI
import UIKit

struct ArtworkView: View {
    let settings: TimerSettings
    var image: UIImage? {
        guard let store = try? SettingsStore.shared(),
              let url = try? store.imageURL(for: settings) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    var body: some View {
        GeometryReader { geometry in
            // Fit the complete artwork to retain both characters and the logo.
            // A blurred fill behind it avoids hard letterboxing on square widgets.
            let artwork = image.map { Image(uiImage: $0) } ?? Image("Artwork")
            ZStack {
                artwork.resizable().scaledToFill().blur(radius: 18).opacity(0.6)
                Color.black.opacity(0.15)
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
            ArtworkView(settings: settings)
            VStack(spacing: 0) {
                if remaining.reached {
                    Text("وصل الموعد").font(.headline)
                } else {
                    Text("\(remaining.days)").font(.system(size: compact ? 26 : 48, weight: .heavy, design: .rounded)).monospacedDigit()
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
