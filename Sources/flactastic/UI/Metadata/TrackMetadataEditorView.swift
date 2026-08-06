import SwiftUI
import AppKit

/// Sheet for editing a single track's embedded file metadata.
/// Changes are written directly to the source file on disk via `MetadataWriter`.
struct TrackMetadataEditorView: View {
    let track: Track

    @Environment(\.dismiss)         private var dismiss
    @Environment(\.metadataWriter)  private var writer
    @Environment(LibraryStore.self) private var library

    // Editable fields — initialised from the track in `init`.
    @State private var title:       String
    @State private var artists:     [String]
    @State private var album:       String
    @State private var year:        String
    @State private var genre:           String
    @State private var secondaryGenres: [String]
    @State private var trackNumber:     String

    // Artwork state
    @State private var artworkData:    Data?
    @State private var artworkChanged: Bool = false
    @State private var artworkRemoved: Bool = false

    // Save progress / error
    @State private var isSaving:    Bool   = false
    @State private var errorMessage: String? = nil

    // Lyrics editor pop-out
    @State private var showLyricsEditor: Bool = false

    init(track: Track) {
        self.track = track
        _title       = State(initialValue: track.title)
        _artists     = State(initialValue: ArtistResolver.explicitlySeparated(track.artist ?? "")
            ?? (track.artist.flatMap { $0.isEmpty ? nil : [$0] } ?? []))
        _album       = State(initialValue: track.album       ?? "")
        _year        = State(initialValue: track.year.map    { "\($0)" } ?? "")
        _genre           = State(initialValue: track.genre ?? "")
        _secondaryGenres = State(initialValue: track.secondaryGenres)
        _trackNumber     = State(initialValue: track.trackNumber.map { "\($0)" } ?? "")
        _artworkData = State(initialValue: track.artwork)
    }

    var body: some View {
        FLSheet(title: "Edit Track", width: 520, height: 500) {
            formBody
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
        .sheet(isPresented: $showLyricsEditor) {
            TrackLyricsEditorView(track: track)
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

    // Artwork picker column
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
            .help("Click to choose an image file")

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

            Text(artworkSupportLabel)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 130)
    }

    private var artworkSupportLabel: String {
        switch track.fileFormat {
        case .wav, .aiff: return "\(track.fileFormat.displayName) · limited"
        default:          return "\(track.fileFormat.displayName) · supported"
        }
    }

    // Metadata fields column
    private var fieldsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            metaField("Song Name",  text: $title,       required: true)
            ArtistsFieldView(artists: $artists)
            metaField("Album",      text: $album)
            HStack(spacing: Theme.Spacing.md) {
                metaField("Year",    text: $year,        numericOnly: true)
                    .frame(maxWidth: .infinity)
                metaField("Track #", text: $trackNumber, numericOnly: true)
                    .frame(maxWidth: .infinity)
            }
            GenreFieldView(text: $genre)
            SecondaryGenresFieldView(genres: $secondaryGenres, primaryGenre: genre)
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
                    Text("*")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
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

    private var footerButtons: some View {
        HStack {
            Button {
                showLyricsEditor = true
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11))
                    Text("Lyrics…")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(isSaving)
            .help("Edit the embedded lyrics for this track")

            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .disabled(isSaving)

            Button(isSaving ? "Saving…" : "Save") { save() }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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
        isSaving = true
        let artChange: MetadataWriter.ArtworkChange
        if artworkRemoved {
            artChange = .removed
        } else if artworkChanged, let d = artworkData {
            artChange = .updated(d)
        } else {
            artChange = .unchanged
        }

        let parsedYear        = Int(year)
        let parsedTrackNumber = Int(trackNumber)
        let snapshot = track
        let cleanedSecondary = secondaryGenres.filter { $0.lowercased() != genre.lowercased() }

        let joinedArtist: String? = {
            let cleaned = artists.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                 .filter { !$0.isEmpty }
            if cleaned.isEmpty { return nil }
            if cleaned.count == 1 { return cleaned[0] }
            return ArtistResolver.joinExplicit(cleaned)
        }()

        Task {
            do {
                let updated = try await writer.write(
                    to: snapshot,
                    title:       title.trimmingCharacters(in: .whitespaces),
                    artist:      joinedArtist,
                    album:       album.isEmpty   ? nil : album,
                    year:            parsedYear,
                    genre:           genre.isEmpty ? nil : genre,
                    secondaryGenres: cleanedSecondary,
                    trackNumber:     parsedTrackNumber,
                    artworkChange: artChange
                )
                await MainActor.run {
                    library.updateTrack(id: snapshot.id, with: updated)
                    ArtworkImageCache.shared.invalidate(id: "track:\(snapshot.id.uuidString)")
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
}
