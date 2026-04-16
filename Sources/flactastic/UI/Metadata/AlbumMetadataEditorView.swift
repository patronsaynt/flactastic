import SwiftUI
import AppKit

/// Sheet for editing shared album-level metadata (album name, artist, year,
/// genre, artwork). Saves the same values to every track in the album by
/// iterating through them via `MetadataWriter`, preserving each track's
/// individual title and track-number.
struct AlbumMetadataEditorView: View {
    let album: Album

    @Environment(\.dismiss)         private var dismiss
    @Environment(\.metadataWriter)  private var writer
    @Environment(LibraryStore.self) private var library

    @State private var albumName:   String
    @State private var artist:      String
    @State private var year:        String
    @State private var genre:       String

    @State private var artworkData:    Data?
    @State private var artworkChanged: Bool = false
    @State private var artworkRemoved: Bool = false

    @State private var isSaving:     Bool   = false
    @State private var savedCount:   Int    = 0
    @State private var errorMessage: String? = nil

    init(album: Album) {
        self.album = album
        _albumName   = State(initialValue: album.name)
        _artist      = State(initialValue: album.artist ?? "")
        _year        = State(initialValue: album.year.map { "\($0)" } ?? "")
        _genre       = State(initialValue: album.genre  ?? "")
        _artworkData = State(initialValue: album.artwork)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(Theme.divider)
            formBody
            Divider().foregroundStyle(Theme.divider)
            footer
        }
        .frame(width: 520, height: 430)
        .background(Theme.surface)
        .alert("Save Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Edit Album")
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

    // MARK: - Form body

    private var formBody: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            artworkSection
            fieldsSection
        }
        .padding(Theme.Spacing.xl)
    }

    private var artworkSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button { pickArtwork() } label: {
                ArtworkView(data: artworkData, size: 130)
                    .overlay(alignment: .bottom) {
                        if artworkData == nil {
                            Text("Click to add")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.bottom, 6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("Click to choose album artwork")

            if artworkData != nil {
                Button("Remove") {
                    artworkData    = nil
                    artworkChanged = false
                    artworkRemoved = true
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .buttonStyle(.plain)
            }
        }
        .frame(width: 130)
    }

    private var fieldsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            metaField("Album Name", text: $albumName, required: true)
            metaField("Artist",     text: $artist)
            HStack(spacing: Theme.Spacing.md) {
                metaField("Year",  text: $year,  width: 80, numericOnly: true)
                metaField("Genre", text: $genre)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text(isSaving
                    ? "Saved \(savedCount) of \(album.tracks.count)…"
                    : "Applies to \(album.tracks.count) track\(album.tracks.count == 1 ? "" : "s")")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func metaField(
        _ label: String,
        text: Binding<String>,
        required: Bool = false,
        width: CGFloat? = nil,
        numericOnly: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if required {
                    Text("*").font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
            }
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.surfaceElevated)
                )
                .frame(width: width)
                .onChange(of: text.wrappedValue) { _, v in
                    if numericOnly {
                        let filtered = v.filter(\.isNumber)
                        if filtered != v { text.wrappedValue = filtered }
                    }
                }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .disabled(isSaving)

            Button(isSaving ? "Saving…" : "Save All") { save() }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .disabled(isSaving || albumName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Actions

    private func pickArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.message = "Choose album artwork"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        artworkData    = data
        artworkChanged = true
        artworkRemoved = false
    }

    private func save() {
        isSaving   = true
        savedCount = 0

        let artChange: MetadataWriter.ArtworkChange
        if artworkRemoved {
            artChange = .removed
        } else if artworkChanged, let d = artworkData {
            artChange = .updated(d)
        } else {
            artChange = .unchanged
        }

        let parsedYear = Int(year)
        let newAlbum   = albumName.trimmingCharacters(in: .whitespaces)
        let newArtist  = artist.isEmpty ? nil : artist
        let newGenre   = genre.isEmpty  ? nil : genre
        let tracks     = album.tracks

        Task {
            var collected: [Track] = []
            var firstError: String? = nil
            for track in tracks {
                do {
                    let updated = try await writer.write(
                        to: track,
                        title:       track.title,           // preserve per-track title
                        artist:      newArtist,
                        album:       newAlbum,
                        year:        parsedYear,
                        genre:       newGenre,
                        trackNumber: track.trackNumber,     // preserve per-track number
                        artworkChange: artChange
                    )
                    collected.append(updated)
                    await MainActor.run { savedCount += 1 }
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                }
            }
            await MainActor.run {
                // Apply all updates atomically so the album grouping key
                // flips in one step instead of migrating track-by-track
                // (which would otherwise make the detail view flash
                // "Album not found" during a rename).
                library.replaceTracks(collected)
                isSaving = false
                if let err = firstError {
                    errorMessage = err
                } else {
                    dismiss()
                }
            }
        }
    }
}
