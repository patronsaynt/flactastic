import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct EditableTrack: Identifiable {
    let id: UUID
    var title: String
    var artists: [String]
    let originalTrack: Track
}

private struct TrackDropDelegate: DropDelegate {
    let toIndex: Int
    @Binding var tracks: [EditableTrack]
    @Binding var draggingIndex: Int?

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let from = draggingIndex, from != toIndex else { return }
        withAnimation(.default) {
            tracks.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: from < toIndex ? toIndex + 1 : toIndex
            )
        }
        draggingIndex = toIndex
    }
}

/// Sheet for editing shared album-level metadata (album name, artist, year,
/// genre, artwork) plus per-track titles and order. Saves all values to every
/// track in the album via `MetadataWriter`, reassigning track numbers to match
/// the reordered list.
struct AlbumMetadataEditorView: View {
    let album: Album

    @Environment(\.dismiss)         private var dismiss
    @Environment(\.metadataWriter)  private var writer
    @Environment(LibraryStore.self) private var library

    @State private var albumName:     String
    @State private var albumArtists:  [String]
    @State private var year:          String
    @State private var genre:         String
    @State private var isCompilation: Bool

    @State private var artworkData:    Data?
    @State private var artworkChanged: Bool = false
    @State private var artworkRemoved: Bool = false
    @State private var pendingCropData: Data?

    @State private var editableTracks: [EditableTrack]
    @State private var draggingIndex:  Int?   = nil

    @State private var isSaving:     Bool    = false
    @State private var savedCount:   Int     = 0
    @State private var errorMessage: String? = nil

    init(album: Album) {
        self.album = album
        _albumName    = State(initialValue: album.name)
        // The single chip-based artist field represents the album-level
        // owning entity. Prefer the existing albumArtist tag; fall back to
        // album.artist (the per-track artist roll-up) so editing a record
        // missing an explicit ALBUMARTIST tag still surfaces a sensible
        // starting list.
        let albumOwnerSource = album.albumArtist ?? album.artist
        _albumArtists = State(initialValue: ArtistResolver.explicitlySeparated(albumOwnerSource ?? "")
            ?? (albumOwnerSource.flatMap { $0.isEmpty ? nil : [$0] } ?? []))
        _year          = State(initialValue: album.year.map { "\($0)" } ?? "")
        _genre         = State(initialValue: album.genre  ?? "")
        _isCompilation = State(initialValue: album.isCompilation)
        _artworkData   = State(initialValue: album.artwork)
        let sorted = album.tracks.sorted {
            ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max)
        }
        _editableTracks = State(initialValue: sorted.map { track in
            let chips = ArtistResolver.explicitlySeparated(track.artist ?? "")
                ?? (track.artist.flatMap { $0.isEmpty ? nil : [$0] } ?? [])
            return EditableTrack(
                id: track.id,
                title: track.title,
                artists: chips,
                originalTrack: track
            )
        })
    }

    var body: some View {
        FLSheet(title: "Edit Album", width: 540, height: 720) {
            VStack(alignment: .leading, spacing: 0) {
                formBody
                Divider().foregroundStyle(Theme.divider)
                trackListSection
            }
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
        .sheet(item: Binding(
            get: { pendingCropData.map { CroppingPayload(data: $0) } },
            set: { if $0 == nil { pendingCropData = nil } }
        )) { payload in
            SquareImageCropperView(sourceData: payload.data) { cropped in
                artworkData    = cropped
                artworkChanged = true
                artworkRemoved = false
            }
        }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            metaField("Album Name",   text: $albumName, required: true)
            ArtistsFieldView(artists: $albumArtists, label: "Album Artist")

            Toggle(isOn: $isCompilation) {
                Text("Compilation")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.checkbox)
            .disabled(isSaving)

            HStack(spacing: Theme.Spacing.md) {
                metaField("Year",  text: $year,  width: 80, numericOnly: true)
                GenreFieldView(text: $genre)
            }

            if isSaving {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Saved \(savedCount) of \(editableTracks.count)…")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)
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

    // MARK: - Track list section

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TRACKS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.md)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(editableTracks.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(Theme.Font.captionMono)
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 24, alignment: .trailing)

                                TextField("", text: $editableTracks[index].title)
                                    .textFieldStyle(.plain)
                                    .font(Theme.Font.body)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                            .fill(Theme.surfaceElevated)
                                    )

                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(
                                        draggingIndex == index
                                            ? Theme.accent.opacity(0.8)
                                            : Theme.textTertiary.opacity(0.6)
                                    )
                                    .frame(width: 18)
                                    .onDrag {
                                        draggingIndex = index
                                        return NSItemProvider(object: "\(index)" as NSString)
                                    }
                            }

                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Color.clear.frame(width: 24)
                                ArtistsFieldView(
                                    artists: $editableTracks[index].artists,
                                    label: nil,
                                    placeholder: "Artists for this track…",
                                    compact: true
                                )
                                Color.clear.frame(width: 18)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, 4)
                        .background(
                            draggingIndex == index
                                ? Theme.surfaceElevated.opacity(0.6)
                                : Color.clear
                        )
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: TrackDropDelegate(
                                toIndex: index,
                                tracks: $editableTracks,
                                draggingIndex: $draggingIndex
                            )
                        )
                    }
                }
                .padding(.bottom, Theme.Spacing.md)
            }
            .frame(maxHeight: 260)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .disabled(isSaving)

            Button(isSaving ? "Saving…" : "Save All") { save() }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .disabled(isSaving || albumName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Helpers

    /// Trim, drop empties, and serialise a chip list into the canonical
    /// `Artist A ; Artist B` form. Returns nil if the list is empty so the
    /// writer treats that as "clear the tag".
    private static func joinedChips(_ chips: [String]) -> String? {
        let cleaned = chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty { return nil }
        if cleaned.count == 1 { return cleaned[0] }
        return ArtistResolver.joinExplicit(cleaned)
    }

    // MARK: - Actions

    private func pickArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.message = "Choose album artwork"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        pendingCropData = data
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
        let newGenre   = genre.isEmpty ? nil : genre

        // Album-level artist — written to the ALBUMARTIST tag on every track.
        // Always treated as explicit: a no-op edit yields the same string the
        // album already had, so the writer's idempotent path still applies.
        let newAlbumArtist: String? = Self.joinedChips(albumArtists)
        let aaChange: MetadataWriter.AlbumArtistChange = {
            let existing = album.albumArtist ?? ""
            let target = newAlbumArtist ?? ""
            if existing == target { return .unchanged }
            return .set(newAlbumArtist)
        }()

        // Compilation tag: only write when the toggle differs from the
        // album's current state (any track flagged) — avoids touching every
        // file on a no-op save.
        let compilationChange: MetadataWriter.CompilationChange = {
            isCompilation == album.isCompilation ? .unchanged : .set(isCompilation)
        }()

        let orderedTracks = editableTracks  // snapshot current order + edited fields

        Task {
            var collected: [Track] = []
            var firstError: String? = nil
            for (index, item) in orderedTracks.enumerated() {
                let newTitle = item.title.trimmingCharacters(in: .whitespaces)
                // Per-track artist: prefer the row's chips. If the user
                // cleared them entirely, inherit from the album-level chips
                // so we never write an empty artist tag for a track that
                // clearly belongs to the album's owner.
                let perTrackArtist = Self.joinedChips(item.artists) ?? newAlbumArtist
                do {
                    let updated = try await writer.write(
                        to: item.originalTrack,
                        title:             newTitle.isEmpty ? item.originalTrack.title : newTitle,
                        artist:            perTrackArtist,
                        album:             newAlbum,
                        year:              parsedYear,
                        genre:             newGenre,
                        trackNumber:       index + 1,
                        artworkChange:     artChange,
                        albumArtistChange: aaChange,
                        compilationChange: compilationChange
                    )
                    collected.append(updated)
                    await MainActor.run { savedCount += 1 }
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                }
            }
            await MainActor.run {
                library.replaceTracks(collected)
                library.invalidateAlbumArtwork(albumID: album.id)
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
