import SwiftUI
import AppKit

/// Root view for the `mini-player` Window scene.
///
/// Layout is *fully explicit* — every region has a `.frame(width:height:)`,
/// no flexible distribution, no `aspectRatio` math, no measurements. The
/// album art and the controls bar are both exactly `columnWidth` wide and
/// stack into a `columnWidth × totalHeight` rectangle. The sidecar appends
/// to the right at a fixed `sidecarWidth × totalHeight`.
struct MiniPlayerView: View {
    @Environment(PlayerState.self) private var player
    @Environment(MiniPlayerPresenter.self) private var presenter

    // ── Locked dimensions ────────────────────────────────────────────────
    static let columnWidth: CGFloat = 280
    static let controlsHeight: CGFloat = 120
    static let totalHeight: CGFloat = columnWidth + controlsHeight   // 400
    static let sidecarWidth: CGFloat = 220
    static let sidecarDivider: CGFloat = 1

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
                .frame(width: Self.columnWidth, height: Self.totalHeight)

            if player.isQueueVisible {
                Divider()
                    .background(Theme.divider)
                MiniPlayerQueueSidecar()
                    .frame(width: Self.sidecarWidth, height: Self.totalHeight)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(height: Self.totalHeight)
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.25), value: player.isQueueVisible)
        .onAppear {
            applyPinned(presenter.isPinned)
            lockWindowSize()
        }
        .onChange(of: presenter.isPinned) { _, pinned in applyPinned(pinned) }
        .onChange(of: player.isQueueVisible) { _, _ in
            DispatchQueue.main.async { lockWindowSize() }
        }
    }

    // MARK: - Main column

    private var mainColumn: some View {
        VStack(spacing: 0) {
            artworkHero
                .frame(width: Self.columnWidth, height: Self.columnWidth)
                .clipped()
            MiniPlayerControls()
                .frame(width: Self.columnWidth, height: Self.controlsHeight)
        }
    }

    private var artworkHero: some View {
        ZStack {
            Theme.background
            if let track = player.currentTrack, let data = track.artwork,
               let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.columnWidth, height: Self.columnWidth)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Theme.surfaceElevated)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 56, weight: .ultraLight))
                            .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    }
            }
        }
    }

    // MARK: - Window sizing

    /// Strip `.resizable` from the mini-player NSWindow and snap its content
    /// size to the canonical dimensions. Called on appear AND every time the
    /// queue toggles — single source of truth, no math drift.
    private func lockWindowSize() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows
                .first(where: { $0.identifier?.rawValue == "mini-player" }) else { return }
            window.styleMask.remove(.resizable)

            let targetWidth = Self.columnWidth
                + (player.isQueueVisible ? Self.sidecarWidth + Self.sidecarDivider : 0)

            // Anchor the top-left so the window doesn't appear to jump when
            // shrinking. Cocoa frames are bottom-left origin.
            let oldTop = window.frame.origin.y + window.frame.size.height
            window.setContentSize(NSSize(width: targetWidth, height: Self.totalHeight))
            var newFrame = window.frame
            newFrame.origin.y = oldTop - newFrame.size.height
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    // MARK: - Always-on-top

    private func applyPinned(_ pinned: Bool) {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue == "mini-player" {
                window.level = pinned ? .floating : .normal
            }
        }
    }
}
