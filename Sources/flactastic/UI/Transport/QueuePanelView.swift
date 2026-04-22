import SwiftUI

struct QueuePanelView: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationRouter.self) private var router

    private func viewAlbumMenu(for track: Track) -> [FLContextMenuItem] {
        [
            .button("View Album", systemImage: "square.grid.2x2") {
                if let albumID = library.album(for: track)?.id {
                    router.navigateToAlbum(id: albumID)
                }
            }
        ]
    }

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

    @State private var draggingTrackID: UUID? = nil
    @State private var dropTargetTrackID: UUID? = nil

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
        let sourceTitle = player.playbackSource.map { "Next from: \($0)" } ?? "Up Next"

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                // ── Now Playing ────────────────────────────────────────────
                if let track = player.currentTrack {
                    listSectionHeader("Now Playing")
                    NowPlayingRow(track: track)
                        .background(Theme.surfaceElevated)
                        .flContextMenu { viewAlbumMenu(for: track) }
                }

                // ── Next in Queue (user-queued tracks, yellow dot) ─────────
                if !queuedUpcoming.isEmpty {
                    listSectionHeader("Next in Queue")
                    ForEach(queuedUpcoming, id: \.track.id) { item in
                        draggableQueueRow(item: item, showQueuedDot: true)
                    }
                }

                // ── Next from Source ───────────────────────────────────────
                if !sourceUpcoming.isEmpty {
                    listSectionHeader(sourceTitle)
                    ForEach(sourceUpcoming, id: \.track.id) { item in
                        draggableQueueRow(item: item, showQueuedDot: false)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func draggableQueueRow(item: (track: Track, engineIndex: Int),
                                   showQueuedDot: Bool) -> some View {
        let trackID = item.track.id
        let isDropTarget = dropTargetTrackID == trackID && draggingTrackID != trackID

        QueueTrackRow(track: item.track, showQueuedDot: showQueuedDot)
            .opacity(draggingTrackID == trackID ? 0.4 : 1.0)
            .overlay(alignment: .top) {
                // Insertion bar shown above the hovered row.
                if isDropTarget {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                player.jumpTo(index: item.engineIndex)
            }
            .flContextMenu { viewAlbumMenu(for: item.track) }
            .draggable(trackID.uuidString) {
                // Drag preview — a shrunken row clone.
                QueueTrackRow(track: item.track, showQueuedDot: showQueuedDot)
                    .frame(width: 280)
                    .background(Theme.surfaceElevated)
                    .cornerRadius(Theme.Radius.sm)
                    .onAppear { draggingTrackID = trackID }
                    .onDisappear {
                        draggingTrackID = nil
                        dropTargetTrackID = nil
                    }
            }
            .dropDestination(for: String.self) { items, _ in
                dropTargetTrackID = nil
                draggingTrackID = nil
                guard let s = items.first, let srcID = UUID(uuidString: s) else {
                    return false
                }
                player.moveTrack(withID: srcID, before: trackID)
                return true
            } isTargeted: { hovering in
                dropTargetTrackID = hovering ? trackID : (dropTargetTrackID == trackID ? nil : dropTargetTrackID)
            }
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
