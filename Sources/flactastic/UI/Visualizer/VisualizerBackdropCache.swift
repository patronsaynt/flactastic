import AppKit
import SwiftUI
import CoreImage

/// Pre-renders the Lyrics backdrop: downsample, gaussian blur, desaturate,
/// darken and tint — once per (image, tint) pair.
///
/// The obvious way to build this backdrop is a stack of SwiftUI modifiers —
/// `.scaleEffect(1.25).blur(radius: 60).grayscale(1).brightness(-0.33)` — but
/// that re-runs a 60pt gaussian over a full-window surface on *every frame*,
/// including all 18 frames of a mode cross-fade while the wheel is also
/// animating. Baking it into a flat image once per track turns the steady
/// state and the transition into a plain image draw.
///
/// `@unchecked Sendable` follows the same audited invariant as
/// `ArtworkImageCache`: rendered images are immutable after creation and only
/// ever read, and `NSCache` is itself thread-safe.
final class VisualizerBackdropCache: @unchecked Sendable {
    static let shared = VisualizerBackdropCache()

    /// Working width for the blur. A 60pt blur destroys detail well below this
    /// anyway, and upscaling the result to the window adds its own softening —
    /// so a small working image is visually indistinguishable and vastly
    /// cheaper than filtering at source resolution.
    private static let workingWidth: CGFloat = 480
    /// Chosen so that, once this is scaled back up to a typical window width,
    /// the result reads like the design's 60pt blur.
    private static let sigma: Double = 20

    private let cache = NSCache<NSString, NSImage>()
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private init() {
        cache.countLimit = 8
    }

    /// See `ArtworkImageCache.ImageBox` — carries a rendered image across an
    /// isolation boundary.
    struct ImageBox: @unchecked Sendable {
        let image: NSImage?
    }

    /// Synchronous memory-cache lookup. Cheap enough for a view body; returns
    /// nil on a miss so the caller can render asynchronously.
    func cached(key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    /// The album's dominant colour, as plain components so the render can run
    /// off the main actor without dragging `NSColor`'s dynamic resolution
    /// along with it.
    struct Tint: Sendable, Equatable {
        let red: Double, green: Double, blue: Double

        /// Stable, low-cardinality cache key — quantised so imperceptibly
        /// different colours share a rendered backdrop.
        var key: String {
            String(format: "%02x%02x%02x",
                   Int(red * 255), Int(green * 255), Int(blue * 255))
        }

        init?(_ color: Color?) {
            guard let color,
                  let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
            red = Double(rgb.redComponent)
            green = Double(rgb.greenComponent)
            blue = Double(rgb.blueComponent)
        }
    }

    func renderAsync(data: Data, tint: Tint?, key: String) async -> ImageBox {
        if let hit = cached(key: key) { return ImageBox(image: hit) }
        return await Task.detached(priority: .userInitiated) { [self] in
            ImageBox(image: render(data: data, tint: tint, key: key))
        }.value
    }

    private func render(data: Data, tint: Tint?, key: String) -> NSImage? {
        if let hit = cached(key: key) { return hit }
        guard let source = CIImage(data: data), !source.extent.isInfinite,
              source.extent.width > 0 else { return nil }

        let scale = min(1, Self.workingWidth / source.extent.width)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent

        // Clamp before blurring so the gaussian samples edge pixels instead of
        // transparency, then crop back to the original frame. Without this the
        // border fades out, which is what the live-blur version needed its
        // 1.25× scale-up to hide.
        let blurred = small
            .clampedToExtent()
            // Sigma is expressed against `workingWidth`, so a source smaller
            // than that blurs proportionally rather than being obliterated.
            .applyingGaussianBlur(sigma: Self.sigma * Double(extent.width / Self.workingWidth))
            .cropped(to: extent)

        var graded = blurred.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputBrightnessKey: -0.33,
            kCIInputContrastKey: 1.15
        ])

        // Tint the now-grayscale ground toward the album's dominant colour.
        // Baking this in replaces a live `.blendMode(.color)` layer, which
        // forced a full-window offscreen compositing pass on every frame —
        // `CIColorMonochrome` over a grayscale source is equivalent, since a
        // colour blend takes hue and saturation from the top layer and
        // luminance from the bottom.
        if let tint {
            graded = graded.applyingFilter("CIColorMonochrome", parameters: [
                kCIInputColorKey: CIColor(red: tint.red, green: tint.green, blue: tint.blue),
                kCIInputIntensityKey: 0.8
            ])
        }

        guard let cgImage = context.createCGImage(graded, from: extent) else { return nil }
        let image = NSImage(cgImage: cgImage, size: extent.size)
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
