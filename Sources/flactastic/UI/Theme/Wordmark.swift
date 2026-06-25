import SwiftUI
import AppKit

/// The FLACtastic logo wordmark.
///
/// The artwork is a flat monochrome PNG resource (the asset catalog is copied
/// raw rather than compiled to a `.car` by SwiftPM, so `Image(name:bundle:)`
/// can't resolve catalog imagesets here). It's rendered as a template image
/// tinted with `Theme.textPrimary`, so the single asset adapts to light/dark
/// like the rest of the chrome.
struct Wordmark: View {
    var height: CGFloat = 15
    var color: Color = Theme.textPrimary

    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "Wordmark", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(height: height)
                .foregroundStyle(color)
                .accessibilityLabel("FLACtastic")
        }
    }
}
