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
    @State private var artist:      String
    @State private var album:       String
    @State private var year:        String
    @State private var genre:       String
    @State private var trackNumber: String

    // Artwork state
    @State private var artworkData:    Data?
    @State private var artworkChanged: Bool = false
    @State private var artworkRemoved: Bool = false

    // Save progress / error
    @State private var isSaving:    Bool   = false
    @State private var errorMessage: String? = nil

    init(track: Track) {
        self.track = track
        _title       = State(initialValue: track.title)
        _artist      = State(initialValue: track.artist      ?? "")
        _album       = State(initialValue: track.album       ?? "")
        _year        = State(initialValue: track.year.map    { "\($0)" } ?? "")
        _genre       = State(initialValue: track.genre       ?? "")
        _trackNumber = State(initialValue: track.trackNumber.map { "\($0)" } ?? "")
        _artworkData = State(initialValue: track.artwork)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(Theme.divider)
            formBody
            Divider().foregroundStyle(Theme.divider)
            footer
        }
        .frame(width: 520, height: 500)
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
            Text("Edit Track")
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
            metaField("Artist",     text: $artist)
            metaField("Album",      text: $album)
            HStack(spacing: Theme.Spacing.md) {
                metaField("Year",      text: $year,   width: 80,  numericOnly: true)
                metaField("Track #",   text: $trackNumber, width: 80, numericOnly: true)
            }
            metaField("Genre",      text: $genre)
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

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .disabled(isSaving)

            Button(isSaving ? "Saving…" : "Save") { save() }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
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

        Task {
            do {
                let updated = try await writer.write(
                    to: snapshot,
                    title:       title.trimmingCharacters(in: .whitespaces),
                    artist:      artist.isEmpty  ? nil : artist,
                    album:       album.isEmpty   ? nil : album,
                    year:        parsedYear,
                    genre:       genre.isEmpty   ? nil : genre,
                    trackNumber: parsedTrackNumber,
                    artworkChange: artChange
                )
                await MainActor.run {
                    library.updateTrack(id: snapshot.id, with: updated)
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
