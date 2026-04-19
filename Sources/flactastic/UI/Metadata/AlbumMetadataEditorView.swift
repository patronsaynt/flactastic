import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct EditableTrack: Identifiable {
    let id: UUID
    var title: String
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

    @State private var albumName:   String
    @State private var artist:      String
    @State private var albumArtist: String
    @State private var year:        String
    @State private var genre:       String

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
        _albumName   = State(initialValue: album.name)
        _artist      = State(initialValue: album.artist ?? "")
        _albumArtist = State(initialValue: album.albumArtist ?? "")
        _year        = State(initialValue: album.year.map { "\($0)" } ?? "")
        _genre       = State(initialValue: album.genre  ?? "")
        _artworkData = State(initialValue: album.artwork)
        let sorted = album.tracks.sorted {
            ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max)
        }
        _editableTracks = State(initialValue: sorted.map {
            EditableTrack(id: $0.id, title: $0.title, originalTrack: $0)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(Theme.divider)
            formBody
            Divider().foregroundStyle(Theme.divider)
            trackListSection
            Divider().foregroundStyle(Theme.divider)
            footer
        }
        .frame(width: 520, height: 660)
        .background(Theme.surface)
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
            metaField("Album Name",   text: $albumName, required: true)
            metaField("Artist",       text: $artist)
            metaField("Album Artist", text: $albumArtist)
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
                    ? "Saved \(savedCount) of \(editableTracks.count)…"
                    : "Applies to \(editableTracks.count) track\(editableTracks.count == 1 ? "" : "s")")
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

    // MARK: - Track list section

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TRACKS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.md)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(editableTracks.indices, id: \.self) { index in
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
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, 2)
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
            .frame(maxHeight: 210)
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

        let parsedYear    = Int(year)
        let newAlbum      = albumName.trimmingCharacters(in: .whitespaces)
        let newArtist     = artist.isEmpty ? nil : artist
        let newGenre      = genre.isEmpty  ? nil : genre
        let trimmedAA     = albumArtist.trimmingCharacters(in: .whitespaces)
        // Only write the albumArtist tag when the field is visibly different
        // from what's already on the album — avoids clobbering existing
        // per-file tags on a no-op edit. Empty field + no existing value = no-op;
        // empty field + existing value = explicit clear.
        let aaChange: MetadataWriter.AlbumArtistChange = {
            let existing = album.albumArtist ?? ""
            if trimmedAA == existing { return .unchanged }
            return .set(trimmedAA.isEmpty ? nil : trimmedAA)
        }()
        let orderedTracks = editableTracks  // snapshot current order + edited titles

        Task {
            var collected: [Track] = []
            var firstError: String? = nil
            for (index, item) in orderedTracks.enumerated() {
                let newTitle = item.title.trimmingCharacters(in: .whitespaces)
                do {
                    let updated = try await writer.write(
                        to: item.originalTrack,
                        title:             newTitle.isEmpty ? item.originalTrack.title : newTitle,
                        artist:            newArtist,
                        album:             newAlbum,
                        year:              parsedYear,
                        genre:             newGenre,
                        trackNumber:       index + 1,
                        artworkChange:     artChange,
                        albumArtistChange: aaChange
                    )
                    collected.append(updated)
                    await MainActor.run { savedCount += 1 }
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                }
            }
            await MainActor.run {
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
