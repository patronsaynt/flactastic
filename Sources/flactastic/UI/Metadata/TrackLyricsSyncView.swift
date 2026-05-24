import SwiftUI

/// Tap-to-sync lyrics editor. The user pastes plain lyrics, presses the
/// spacebar (or the on-screen Tap button) at the start of each line, and
/// the sheet records `player.currentTime` per line. On Save, the lines
/// are re-emitted as LRC into the bound `lyricsText`.
struct TrackLyricsSyncView: View {
    let track: Track
    @Binding var lyricsText: String

    @Environment(\.dismiss)        private var dismiss
    @Environment(PlayerState.self) private var player

    @State private var lines: [String] = []
    @State private var timestamps: [TimeInterval?] = []
    @State private var cursor: Int = 0
    @State private var didStartPlayback: Bool = false

    var body: some View {
        FLSheet(title: "Sync Lyrics", width: 620, height: 620) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                instructions
                transportRow
                Divider().foregroundStyle(Theme.divider)
                linesList
                actionRow
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            footerButtons
        }
        // Hidden affordance: spacebar stamps the next line. Sized to zero
        // so it doesn't take visual space, but stays in the responder chain.
        .background {
            Button("", action: tapBeat)
                .keyboardShortcut(.space, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .onAppear { onAppear() }
        .onDisappear { player.isLyricsSyncActive = false }
    }

    // MARK: - Sections

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Press the spacebar — or click **Tap** — when each line begins.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("Use Back to undo a stamp; Skip leaves a line untimed.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var transportRow: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            HStack(spacing: Theme.Spacing.md) {
                transportButton(systemName: "backward.end.fill", help: "Restart") {
                    player.engine.seek(to: 0)
                }
                transportButton(systemName: "gobackward.5", help: "Back 3s") {
                    player.engine.seek(to: max(0, player.currentTime - 3))
                }
                transportButton(
                    systemName: player.isPlaying ? "pause.fill" : "play.fill",
                    help: player.isPlaying ? "Pause" : "Play"
                ) {
                    player.engine.togglePlayPause()
                }
                transportButton(systemName: "goforward.5", help: "Forward 3s") {
                    let bound = player.duration ?? .greatestFiniteMagnitude
                    player.engine.seek(to: min(bound, player.currentTime + 3))
                }

                Spacer()

                Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration ?? 0))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func transportButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var linesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        lineRow(index: idx, line: line)
                            .id(idx)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.surfaceElevated.opacity(0.4))
            )
            .onChange(of: cursor) { _, newCursor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(min(newCursor, lines.count - 1), anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func lineRow(index: Int, line: String) -> some View {
        let isActive = index == cursor
        let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            // Active indicator dot
            Circle()
                .fill(isActive ? Theme.accent : Color.clear)
                .frame(width: 6, height: 6)

            // Timestamp column
            Text(timestamps[index].map(formatTime) ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(timestamps[index] != nil ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 56, alignment: .leading)

            // Line text
            Text(isBlank ? " " : line)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(isActive ? Theme.surfaceHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { cursor = index }
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: stepBack) {
                Label("Back", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(cursor == 0 && timestamps.allSatisfy { $0 == nil })

            Button(action: skip) {
                Label("Skip", systemImage: "forward.frame")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(cursor >= lines.count)

            Button(action: tapBeat) {
                Label("Tap", systemImage: "hand.tap.fill")
            }
            .buttonStyle(PillButtonStyle(isPrimary: true))
            .disabled(cursor >= lines.count)

            Spacer()

            Button(role: .destructive, action: resetAll) {
                Text("Reset all")
            }
            .buttonStyle(.plain)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private var footerButtons: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            if hasOutOfOrderStamps {
                Text("Some timestamps are out of order — saving anyway.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                Button("Save") { save() }
                    .buttonStyle(PillButtonStyle(isPrimary: true))
            }
        }
    }

    // MARK: - Actions

    private func tapBeat() {
        guard cursor < lines.count else { return }
        timestamps[cursor] = player.currentTime
        cursor += 1
    }

    private func stepBack() {
        guard cursor > 0 else { return }
        cursor -= 1
        timestamps[cursor] = nil
    }

    private func skip() {
        guard cursor < lines.count else { return }
        cursor += 1
    }

    private func resetAll() {
        timestamps = Array(repeating: nil, count: lines.count)
        cursor = 0
    }

    private func save() {
        let pairs = zip(timestamps, lines).map { ($0, $1) }
        lyricsText = Lyrics.serializeLRC(lines: pairs)
        dismiss()
    }

    // MARK: - Lifecycle

    private func onAppear() {
        seedFromExistingText()
        player.isLyricsSyncActive = true

        // Start the right track playing if it isn't already current.
        if player.currentTrack?.id != track.id {
            player.startFreshQueue([track])
            didStartPlayback = true
        }
    }

    /// Initialise `lines` and `timestamps` from `lyricsText`. If the input
    /// already contains LRC brackets, parse them so the user can refine
    /// existing stamps; otherwise split on newlines with all timestamps nil.
    private func seedFromExistingText() {
        let raw = lyricsText
        let hasLRC = raw.range(of: #"\[\d{1,2}:\d{2}"#, options: .regularExpression) != nil
        if hasLRC {
            let parsed = Lyrics.parseLRC(raw)
            // parseLRC drops blank lines without timestamps. Restore the
            // user's source order by also walking the raw text.
            // For the common case (well-formed LRC) the parsed list maps
            // 1:1 to the source's non-blank lines, which is fine.
            lines = parsed.lines.map { $0.text }
            timestamps = parsed.lines.map { $0.timestamp }
        } else {
            let split = raw.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
            lines = split
            timestamps = Array(repeating: nil, count: split.count)
        }

        // Move cursor to the first un-stamped line.
        cursor = timestamps.firstIndex(where: { $0 == nil }) ?? lines.count
    }

    // MARK: - Helpers

    private var hasOutOfOrderStamps: Bool {
        let stamps = timestamps.compactMap { $0 }
        return zip(stamps, stamps.dropFirst()).contains { $0 > $1 }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = seconds
        let m = Int(total) / 60
        let s = total.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", m, s)
    }
}
