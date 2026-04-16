import SwiftUI

struct QueuePanelView: View {
    @Environment(PlayerState.self) private var player

    /// All upcoming entries (engine indices > currentIndex).
    private var upcoming: [(track: Track, engineIndex: Int)] {
        let q = player.queue
        let start = player.currentIndex + 1
        guard start < q.count else { return [] }
        return (start..<q.count).map { (q[$0], $0) }
    }

    private var queuedUpcoming: [(track: Track, engineIndex: Int)] {
        upcoming.filter { player.isUserQueued($0.track) }
    }

    private var sourceUpcoming: [(track: Track, engineIndex: Int)] {
        upcoming.filter { !player.isUserQueued($0.track) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(Theme.divider)

            if player.currentTrack == nil && player.queue.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
    }

    // MARK: - Queue list

    private var queueList: some View {
        // Base engine index for the source section — immediately after queued items.
        let queuedBase = player.currentIndex + 1
        let sourceBase = queuedBase + queuedUpcoming.count
        let sourceTitle = player.playbackSource.map { "Next from: \($0)" } ?? "Up Next"

        return List {
            // ── Now Playing ────────────────────────────────────────────────
            if let track = player.currentTrack {
                Section {
                    NowPlayingRow(track: track)
                        .listRowBackground(Theme.surfaceElevated)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .moveDisabled(true)
                } header: {
                    listSectionHeader("Now Playing")
                }
            }

            // ── Next in Queue (user-queued tracks, yellow dot) ─────────────
            if !queuedUpcoming.isEmpty {
                Section {
                    ForEach(queuedUpcoming, id: \.track.id) { item in
                        QueueTrackRow(track: item.track, showQueuedDot: true)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                player.jumpTo(index: item.engineIndex)
                            }
                    }
                    .onMove { source, destination in
                        player.moveQueueItems(
                            from: source, to: destination,
                            baseEngineIndex: queuedBase
                        )
                    }
                } header: {
                    listSectionHeader("Next in Queue")
                }
            }

            // ── Next from Source ───────────────────────────────────────────
            if !sourceUpcoming.isEmpty {
                Section {
                    ForEach(sourceUpcoming, id: \.track.id) { item in
                        QueueTrackRow(track: item.track, showQueuedDot: false)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                player.jumpTo(index: item.engineIndex)
                            }
                    }
                    .onMove { source, destination in
                        player.moveQueueItems(
                            from: source, to: destination,
                            baseEngineIndex: sourceBase
                        )
                    }
                } header: {
                    listSectionHeader(sourceTitle)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Queue")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    player.isQueueVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Section header

    private func listSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.headline)
            .foregroundStyle(Theme.textPrimary)
            .textCase(.none)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text("Queue is empty")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textTertiary)
            Text("Right-click an album or track to queue it")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.lg)
    }
}

// MARK: - Now Playing row (larger, focal)

private struct NowPlayingRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ArtworkView(data: track.artwork, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                if let artist = track.artist {
                    Text(artist)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - Regular queue row

private struct QueueTrackRow: View {
    let track: Track
    let showQueuedDot: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            queuedDot.frame(width: 8)

            ArtworkView(data: track.artwork, size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let artist = track.artist {
                    Text(artist)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(FormatUtils.formatDuration(track.duration))
                .font(Theme.Font.captionMono)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()

            // Drag handle — visual affordance for reordering
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary.opacity(0.5))
                .frame(width: 18)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var queuedDot: some View {
        if showQueuedDot {
            Circle()
                .fill(Color.yellow)
                .frame(width: 6, height: 6)
        } else {
            Color.clear.frame(width: 6, height: 6)
        }
    }
}
