import SwiftUI

struct AlbumArtVisualizerView: View {
    @Environment(PlayerState.self) private var player
    let mode: VisualizerMode

    var body: some View {
        GeometryReader { geo in
            let minSide = min(geo.size.width, geo.size.height)
            switch mode {
            case .albumArtLarge:
                centered(size: minSide * 0.62, showDetails: false, geo: geo)
            case .albumArtLargeDetails:
                centered(size: minSide * 0.55, showDetails: true, geo: geo)
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

    @ViewBuilder
    private func horizontalBanner(geo: GeometryProxy) -> some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        let artSize: CGFloat = min(160, geo.size.height * 0.35)

        VStack {
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.lg) {
                ArtworkView(data: track?.artwork, size: artSize)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    MarqueeText(
                        text: track?.title ?? "—",
                        font: .system(size: 30),
                        weight: .bold,
                        foregroundStyle: AnyShapeStyle(Theme.textPrimary)
                    )
                    MarqueeText(
                        text: artist,
                        font: Theme.Font.title,
                        foregroundStyle: AnyShapeStyle(Theme.textSecondary)
                    )
                    if let album, !album.isEmpty {
                        MarqueeText(
                            text: album,
                            font: Theme.Font.body,
                            foregroundStyle: AnyShapeStyle(Theme.textTertiary)
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, Theme.Spacing.xxl)
            Spacer(minLength: 0)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    @ViewBuilder
    private func centered(size: CGFloat, showDetails: Bool, geo: GeometryProxy) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            ArtworkView(data: player.currentTrack?.artwork, size: size)
                .scaleEffect(player.isPlaying ? 1.0 : 0.985)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: player.isPlaying)
            if showDetails {
                detailsBlock
            }
            Spacer(minLength: 0)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private var detailsBlock: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: Theme.Spacing.xs) {
            MarqueeText(
                text: track?.title ?? "—",
                font: Theme.Font.title,
                foregroundStyle: AnyShapeStyle(Theme.textPrimary),
                alignment: .center
            )
            MarqueeText(
                text: artist,
                font: Theme.Font.body,
                foregroundStyle: AnyShapeStyle(Theme.textSecondary),
                alignment: .center
            )
            if let album, !album.isEmpty {
                MarqueeText(
                    text: album,
                    font: Theme.Font.caption,
                    foregroundStyle: AnyShapeStyle(Theme.textTertiary),
                    alignment: .center
                )
            }
            progressBar
                .frame(maxWidth: 360)
                .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var progressBar: some View {
        GeometryReader { g in
            let total = max(player.duration ?? 0, 0.0001)
            let frac = max(0, min(1, player.currentTime / total))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.divider)
                    .frame(height: 3)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: g.size.width * CGFloat(frac), height: 3)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Wheel

struct AlbumArtWheelView: View {
    @Environment(PlayerState.self) private var player

    /// Half-window of covers to render either side of the current one.
    private let halfWindow: Int = 4

    var body: some View {
        GeometryReader { geo in
            let minSide = min(geo.size.width, geo.size.height)
            let centerSize = minSide * 0.36
            let spacing = centerSize * 0.62

            VStack(spacing: Theme.Spacing.xl) {
                Spacer(minLength: 0)
                ZStack {
                    ForEach(visibleEntries(), id: \.id) { entry in
                        let offset = CGFloat(entry.relativeIndex)
                        let absDistance = abs(offset)
                        let scale = max(0.55, 1.0 - absDistance * 0.18)
                        let opacity = max(0.18, 1.0 - absDistance * 0.28)
                        ArtworkView(data: entry.track.artwork, size: centerSize)
                            .scaleEffect(scale)
                            .opacity(opacity)
                            .offset(x: offset * spacing)
                            .zIndex(-absDistance)
                    }
                }
                .frame(height: centerSize)
                .animation(.spring(response: 0.55, dampingFraction: 0.82),
                           value: player.currentIndex)

                wheelDetails
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var wheelDetails: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: Theme.Spacing.xs) {
            MarqueeText(
                text: track?.title ?? "—",
                font: Theme.Font.title,
                foregroundStyle: AnyShapeStyle(Theme.textPrimary),
                alignment: .center
            )
            MarqueeText(
                text: artist,
                font: Theme.Font.body,
                foregroundStyle: AnyShapeStyle(Theme.textSecondary),
                alignment: .center
            )
            if let album, !album.isEmpty {
                MarqueeText(
                    text: album,
                    font: Theme.Font.caption,
                    foregroundStyle: AnyShapeStyle(Theme.textTertiary),
                    alignment: .center
                )
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, Theme.Spacing.xxl)
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
