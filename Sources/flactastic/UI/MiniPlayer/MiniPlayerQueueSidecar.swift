import SwiftUI

/// Right-side queue panel for the pop-out mini player. Slimmed down from
/// `QueuePanelView` for the narrower window — same data model and engine
/// APIs (`player.queue`, `player.removeFromQueue(at:)`, `player.jumpTo(_:)`,
/// `player.moveTrack(withID:before:)`), reduced visual chrome.
struct MiniPlayerQueueSidecar: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library

    @State private var draggingTrackID: UUID? = nil
    @State private var dropTargetTrackID: UUID? = nil

    /// All upcoming entries (engine indices > currentIndex).
    private var upcoming: [(track: Track, engineIndex: Int)] {
        let q = player.queue
        let start = player.currentIndex + 1
        guard start < q.count else { return [] }
        return (start..<q.count).map { (q[$0], $0) }
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
        .frame(width: 220)
        .background(Theme.surface)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Up Next")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    player.isQueueVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Hide queue")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - List

    private var queueList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if let track = player.currentTrack {
                    nowPlayingRow(track)
                        .background(Theme.surfaceElevated)
                }

                if !upcoming.isEmpty {
                    sectionLabel("Next Up")
                    ForEach(upcoming, id: \.track.id) { item in
                        draggableRow(item: item, showQueuedDot: player.isUserQueued(item.track))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - Rows

    private func nowPlayingRow(_ track: Track) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ArtworkView(data: track.artwork, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                if let artist = ArtistResolver.displayString(track.artist) {
                    Text(artist)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private func draggableRow(item: (track: Track, engineIndex: Int),
                              showQueuedDot: Bool) -> some View {
        let trackID = item.track.id
        let isDropTarget = dropTargetTrackID == trackID && draggingTrackID != trackID

        sidecarTrackRow(item.track, showQueuedDot: showQueuedDot)
            .opacity(draggingTrackID == trackID ? 0.4 : 1.0)
            .overlay(alignment: .top) {
                if isDropTarget {
                    Rectangle().fill(Theme.accent).frame(height: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                player.jumpTo(index: item.engineIndex)
            }
            .contextMenu {
                Button("Remove from Queue") {
                    player.removeFromQueue(at: item.engineIndex)
                }
            }
            .draggable(trackID.uuidString) {
                sidecarTrackRow(item.track, showQueuedDot: showQueuedDot)
                    .frame(width: 240)
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

    private func sidecarTrackRow(_ track: Track, showQueuedDot: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            queuedDot(showQueuedDot).frame(width: 8)
            ArtworkView(data: track.artwork, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(Theme.Font.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let artist = ArtistResolver.displayString(track.artist) {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary.opacity(0.5))
                .frame(width: 16)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func queuedDot(_ show: Bool) -> some View {
        if show {
            Circle().fill(Color.yellow).frame(width: 6, height: 6)
        } else {
            Color.clear.frame(width: 6, height: 6)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
            Text("Queue is empty")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.lg)
    }
}
