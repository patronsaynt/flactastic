import AppKit
import SwiftUI

/// Loads remote cover art and samples a vibrant accent color from it, so the
/// Albums & Tracks screen can tint itself to match the selected release.
enum ArtworkAccent {
    /// Fetch and decode the image at `url`, returning it alongside a legible
    /// accent color sampled from its most saturated dominant hue. Returns the
    /// image with `accent == nil` when the art has no suitably vibrant color
    /// (callers fall back to the default tint). Returns `nil` on any failure.
    static func load(_ url: URL) async -> (image: NSImage, accent: Color?)? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        return (image, dominant(from: image))
    }

    /// Downsample to a small bitmap, bucket pixels by coarse RGB, and pick the
    /// bucket with the greatest saturation-weighted mass — skipping near-black,
    /// near-white, and washed-out pixels so the result reads as a brand accent.
    static func dominant(from image: NSImage) -> Color? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let w = 32, h = 32
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        struct Bucket { var weight = 0.0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var buckets: [Int: Bucket] = [:]

        for i in stride(from: 0, to: data.count, by: 4) {
            let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let sat = maxC == 0 ? 0 : (maxC - minC) / maxC
            // Skip near-black, near-white, and low-saturation (grey) pixels.
            if maxC < 0.12 || sat < 0.18 { continue }
            let key = (Int(r * 4) << 6) | (Int(g * 4) << 3) | Int(b * 4)
            var e = buckets[key] ?? Bucket()
            e.weight += sat; e.r += r * sat; e.g += g * sat; e.b += b * sat
            buckets[key] = e
        }

        guard let top = buckets.max(by: { $0.value.weight < $1.value.weight })?.value,
              top.weight > 0 else { return nil }

        let base = NSColor(srgbRed: top.r / top.weight,
                           green: top.g / top.weight,
                           blue: top.b / top.weight, alpha: 1)
        guard let c = base.usingColorSpace(.sRGB) else { return nil }

        // Lift saturation + brightness so the tint stays legible on the dark UI.
        var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, alpha: CGFloat = 0
        c.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)
        sat = max(sat, 0.55)
        bright = max(bright, 0.72)
        return Color(nsColor: NSColor(hue: hue, saturation: sat, brightness: bright, alpha: 1))
    }
}
