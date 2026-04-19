import SwiftUI
import AppKit

/// Lightweight identifiable wrapper so callers can drive `.sheet(item:)`
/// with raw `Data` from a file picker.
struct CroppingPayload: Identifiable {
    let id = UUID()
    let data: Data
}

/// Sheet that lets the user pan + zoom an image inside a fixed square crop
/// window, then returns the cropped image as PNG `Data` via `onComplete`.
///
/// Used by album and playlist artwork editors so all stored cover images are
/// guaranteed 1:1, avoiding distortion in the grid/row UI.
struct SquareImageCropperView: View {
    let sourceData: Data
    let onComplete: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    private let cropSize: CGFloat = 320
    private let outputPixelSize: CGFloat = 1000
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    private var cgImage: CGImage? {
        guard let nsImage = NSImage(data: sourceData) else { return nil }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(Theme.divider)
            cropArea
                .padding(Theme.Spacing.xl)
            zoomSlider
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)
            Divider().foregroundStyle(Theme.divider)
            footer
        }
        .frame(width: 440, height: 540)
        .background(Theme.surface)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Crop Cover")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Crop area

    private var cropArea: some View {
        ZStack {
            Color.black
            if let nsImage = NSImage(data: sourceData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cropSize, height: cropSize)
                    .scaleEffect(scale)
                    .offset(offset)
            }
        }
        .frame(width: cropSize, height: cropSize)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let proposed = CGSize(
                        width: dragStart.width + value.translation.width,
                        height: dragStart.height + value.translation.height
                    )
                    offset = clamp(offset: proposed, scale: scale)
                }
                .onEnded { _ in dragStart = offset }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Zoom slider

    private var zoomSlider: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Slider(value: Binding(
                get: { scale },
                set: { newScale in
                    scale = newScale
                    offset = clamp(offset: offset, scale: newScale)
                    dragStart = offset
                }
            ), in: minScale...maxScale)
            .tint(Theme.accent)
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)

            Button("Use") { commit() }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(cgImage == nil)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Geometry helpers

    /// Image dimensions, in *preview-square* coordinates, after the initial
    /// aspect-fill into the cropSize square (before user zoom is applied).
    private func filledSize() -> CGSize? {
        guard let cg = cgImage else { return nil }
        let imgW = CGFloat(cg.width)
        let imgH = CGFloat(cg.height)
        guard imgW > 0, imgH > 0 else { return nil }
        let fillScale = cropSize / min(imgW, imgH)
        return CGSize(width: imgW * fillScale, height: imgH * fillScale)
    }

    /// Clamp the user offset so the image always covers the crop window for
    /// the given zoom level — prevents panning past edges.
    private func clamp(offset: CGSize, scale: CGFloat) -> CGSize {
        guard let filled = filledSize() else { return .zero }
        let renderedW = filled.width * scale
        let renderedH = filled.height * scale
        let maxX = max(0, (renderedW - cropSize) / 2)
        let maxY = max(0, (renderedH - cropSize) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    // MARK: - Crop + encode

    private func commit() {
        guard let cg = cgImage, let filled = filledSize() else { return }

        // Map the visible crop window back into source-pixel coordinates.
        // pixelsPerPreviewPoint converts from preview-square points to source
        // pixels at the current effective zoom level.
        let totalScale = scale
        let pixelsPerPreviewPoint = CGFloat(cg.width) / filled.width / totalScale

        let srcSize = cropSize * pixelsPerPreviewPoint

        let renderedW = filled.width * totalScale
        let renderedH = filled.height * totalScale

        // Top-left of the visible crop window in source pixels:
        // image is centered at (cropSize/2 + offset, cropSize/2 + offset);
        // window top-left is (0, 0) in container space, so in image-rendered
        // space the window starts at (renderedW/2 - cropSize/2 - offset, …)
        let srcX = (renderedW / 2 - cropSize / 2 - offset.width) * pixelsPerPreviewPoint
        let srcY = (renderedH / 2 - cropSize / 2 - offset.height) * pixelsPerPreviewPoint

        let cropRect = CGRect(x: srcX, y: srcY, width: srcSize, height: srcSize).integral
        guard let cropped = cg.cropping(to: cropRect) else { return }

        let outSize = Int(outputPixelSize)
        guard let ctx = CGContext(
            data: nil,
            width: outSize,
            height: outSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outSize, height: outSize))
        guard let outCG = ctx.makeImage() else { return }

        let rep = NSBitmapImageRep(cgImage: outCG)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }

        onComplete(data)
        dismiss()
    }
}
