import SwiftUI

struct AlbumArtVisualizerView: View {
    @Environment(PlayerState.self) private var player
    let mode: VisualizerMode

    var body: some View {
        GeometryReader { geo in
            switch mode {
            case .albumArtLarge:
                largeArt(geo: geo)
            case .albumArtLargeDetails:
                largeArtWithDetails(geo: geo)
            case .albumArtSmallDetails:
                horizontalBanner(geo: geo)
            case .albumArtWheel:
                AlbumArtWheelView()
                    .frame(width: geo.size.width, height: geo.size.height)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Large Art

    /// Artwork alone, breathing, wrapped in a soft halo. The design sizes it
    /// at 46vh with a 320pt floor; the width clamp keeps it on screen in a
    /// narrow window.
    private func largeArt(geo: GeometryProxy) -> some View {
        let size = min(max(geo.size.height * 0.46, 320),
                       geo.size.width * 0.9, geo.size.height * 0.9)
        return ZStack {
            halo(around: size)
            ArtworkView(data: player.currentTrack?.artwork, size: size)
                .scaleEffect(player.isPlaying ? 1.0 : 0.985)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: player.isPlaying)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    /// The `radial-gradient` bloom behind the large artwork — inset −14% of
    /// the art's size, blurred, and clear by two-thirds of its radius.
    private func halo(around size: CGFloat) -> some View {
        let diameter = size * 1.28
        return Circle()
            .fill(
                RadialGradient(
                    colors: [VisualizerPalette.mark.opacity(0.10),
                             VisualizerPalette.mark.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.34
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: 18)
            .allowsHitTesting(false)
    }

    // MARK: - Large Art + Details

    private func largeArtWithDetails(geo: GeometryProxy) -> some View {
        let size = min(max(geo.size.height * 0.40, 280),
                       geo.size.width * 0.85, geo.size.height * 0.66)
        return VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            ArtworkView(data: player.currentTrack?.artwork, size: size)
                .scaleEffect(player.isPlaying ? 1.0 : 0.985)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: player.isPlaying)
            centeredDetails
            Spacer(minLength: 0)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private var centeredDetails: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: Theme.Spacing.xs) {
            MarqueeText(
                text: track?.title ?? "—",
                font: .system(size: 17, weight: .semibold),
                foregroundStyle: AnyShapeStyle(Theme.textPrimary),
                alignment: .center
            )
            MarqueeText(
                text: artist,
                font: .system(size: 13),
                foregroundStyle: AnyShapeStyle(Theme.textSecondary),
                alignment: .center
            )
            if let album, !album.isEmpty {
                MarqueeText(
                    text: album,
                    font: .system(size: 11),
                    foregroundStyle: AnyShapeStyle(Theme.textTertiary),
                    alignment: .center
                )
            }
            TechSpecLabel(track: track)
                .padding(.top, 14)
            PlaybackProgressBar()
                .frame(maxWidth: 360)
                .padding(.top, Theme.Spacing.md)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, Theme.Spacing.xl)
    }

    // MARK: - Small Art + Details

    private func horizontalBanner(geo: GeometryProxy) -> some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        let artSize: CGFloat = min(160, geo.size.height * 0.35)

        return HStack(spacing: Theme.Spacing.xl) {
            ArtworkView(data: track?.artwork, size: artSize)

            VStack(alignment: .leading, spacing: 6) {
                MarqueeText(
                    text: track?.title ?? "—",
                    font: .system(size: 30),
                    weight: .bold,
                    foregroundStyle: AnyShapeStyle(Theme.textPrimary)
                )
                MarqueeText(
                    text: artist,
                    font: .system(size: 17, weight: .semibold),
                    foregroundStyle: AnyShapeStyle(Theme.textSecondary)
                )
                if let album, !album.isEmpty {
                    MarqueeText(
                        text: album,
                        font: .system(size: 13),
                        foregroundStyle: AnyShapeStyle(Theme.textTertiary)
                    )
                }
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(width: 28, height: 1)
                    TechSpecLabel(track: track)
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, Theme.Spacing.xxl)
        .frame(width: geo.size.width, height: geo.size.height)
    }
}

// MARK: - Cover Wheel

struct AlbumArtWheelView: View {
    @Environment(PlayerState.self) private var player

    /// Two covers either side of the current one — the design shows five.
    private let halfWindow: Int = 2

    var body: some View {
        GeometryReader { geo in
            let centerSize = min(300, min(geo.size.width, geo.size.height) * 0.42)
            // The design's 186pt step against a 300pt cover; scaled so the
            // overlap reads the same at any cover size.
            let spacing = centerSize * (186.0 / 300.0)

            VStack(spacing: 40) {
                Spacer(minLength: 0)
                ZStack {
                    ForEach(visibleEntries(), id: \.id) { entry in
                        cover(entry, size: centerSize, spacing: spacing)
                    }
                }
                .frame(height: centerSize)
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.75),
                           value: player.currentIndex)

                wheelDetails
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// One cover in the wheel. Outer covers shrink, fade, desaturate and blur
    /// with distance from the current track, per the design's falloff curves.
    private func cover(_ entry: Entry, size: CGFloat, spacing: CGFloat) -> some View {
        let offset = CGFloat(entry.relativeIndex)
        let distance = abs(offset)
        let scale: CGFloat = max(0.55, 1.0 - distance * 0.18)
        let opacity: Double = max(0.18, 1.0 - Double(distance) * 0.3)
        let grayscale: Double = entry.relativeIndex == 0 ? 0 : 0.45
        return ArtworkView(data: entry.track.artwork, size: size)
            .grayscale(grayscale)
            .blur(radius: distance * 1.6)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(x: offset * spacing)
            .zIndex(-Double(distance))
    }

    private var wheelDetails: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: Theme.Spacing.xs) {
            MarqueeText(
                text: track?.title ?? "—",
                font: .system(size: 17, weight: .semibold),
                foregroundStyle: AnyShapeStyle(Theme.textPrimary),
                alignment: .center
            )
            MarqueeText(
                text: artist,
                font: .system(size: 13),
                foregroundStyle: AnyShapeStyle(Theme.textSecondary),
                alignment: .center
            )
            if let album, !album.isEmpty {
                MarqueeText(
                    text: album,
                    font: .system(size: 11),
                    foregroundStyle: AnyShapeStyle(Theme.textTertiary),
                    alignment: .center
                )
            }
            queueDots
                .padding(.top, 18)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, Theme.Spacing.xxl)
    }

    /// One dot per cover in the visible window, the current track's filled and
    /// enlarged. Gives the wheel a sense of position within the queue.
    private var queueDots: some View {
        HStack(spacing: 6) {
            ForEach(visibleEntries(), id: \.id) { entry in
                let isCurrent = entry.relativeIndex == 0
                Circle()
                    .fill(isCurrent ? Theme.accent : Theme.accent.opacity(0.22))
                    .frame(width: 5, height: 5)
                    .scaleEffect(isCurrent ? 1.4 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: player.currentIndex)
    }

    private struct Entry: Identifiable {
        let id: UUID
        let track: Track
        let relativeIndex: Int
    }

    private func visibleEntries() -> [Entry] {
        let q = player.queue
        guard !q.isEmpty else { return [] }
        let cur = player.currentIndex
        var out: [Entry] = []
        for delta in -halfWindow...halfWindow {
            let idx = cur + delta
            guard idx >= 0, idx < q.count else { continue }
            out.append(Entry(id: q[idx].id, track: q[idx], relativeIndex: delta))
        }
        return out
    }
}
