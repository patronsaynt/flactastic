import SwiftUI

/// Sheet for hand-editing the LYRICS tag on a single track. Pre-fills with
/// whatever's already embedded in the file (or already cached from lrclib);
/// saving writes back to the file via `MetadataWriter` and refreshes the
/// shared lyrics cache so the visualizer picks up the change instantly.
struct TrackLyricsEditorView: View {
    let track: Track

    @Environment(\.dismiss)               private var dismiss
    @Environment(\.metadataWriter)        private var writer
    @Environment(LyricsRemoteCache.self)  private var cache

    @State private var text: String = ""
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSyncEditor: Bool = false

    var body: some View {
        FLSheet(title: "Edit Lyrics", width: 560, height: 560) {
            body(loaded: !isLoading)
        } footer: {
            footerButtons
        }
        .alert("Save Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await load() }
        .sheet(isPresented: $showSyncEditor) {
            TrackLyricsSyncView(track: track, lyricsText: $text)
        }
    }

    @ViewBuilder
    private func body(loaded: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Paste plain lyrics or LRC-formatted synced lyrics. Synced lines look like \u{200B}[01:23.45]Lyric\u{200B}.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.surfaceElevated)
                if loaded {
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    showSyncEditor = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "metronome")
                            .font(.system(size: 11))
                        Text("Sync…")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Tap on the beat to add timestamps to each line")

                Spacer()
                if !text.isEmpty {
                    Button("Clear") { text = "" }
                        .buttonStyle(.plain)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .disabled(isSaving)
            Button(isSaving ? "Saving…" : "Save") { save() }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .disabled(isSaving || isLoading)
        }
    }

    // MARK: - Actions

    private func load() async {
        // Prefer the file's embedded LYRICS tag — that's the source of truth
        // the user is editing. Fall back to whatever's in the in-memory cache
        // (e.g. just-fetched lrclib content not yet flushed to file).
        var initial: String = ""
        if let stored = try? await writer.readLyrics(from: track),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initial = stored
        } else {
            let key = LyricsCacheKey.make(
                artist: track.artist ?? track.albumArtist,
                title: track.title,
                duration: track.duration
            )
            if let entry = cache.entry(forKey: key), !entry.notFound {
                initial = entry.syncedLyrics ?? entry.plainLyrics ?? ""
            }
        }
        await MainActor.run {
            text = initial
            isLoading = false
        }
    }

    private func save() {
        isSaving = true
        let payload = text
        let snapshot = track
        Task {
            do {
                try await writer.writeLyrics(to: snapshot, lyrics: payload.isEmpty ? nil : payload)
                await MainActor.run {
                    refreshCache(with: payload)
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    /// Update the in-memory lyrics cache so the visualizer picks up the edit
    /// without waiting for the next track change. Empty input clears the
    /// cached entry entirely (so the next play re-reads from file or
    /// re-fetches).
    private func refreshCache(with payload: String) {
        let key = LyricsCacheKey.make(
            artist: track.artist ?? track.albumArtist,
            title: track.title,
            duration: track.duration
        )
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cache.setEntry(LyricsCacheEntry(key: key, notFound: false))
            return
        }
        let looksSynced = trimmed.range(
            of: #"\[\d{1,2}:\d{2}"#,
            options: .regularExpression
        ) != nil
        cache.setEntry(LyricsCacheEntry(
            key: key,
            plainLyrics: looksSynced ? nil : trimmed,
            syncedLyrics: looksSynced ? trimmed : nil
        ))
    }
}
