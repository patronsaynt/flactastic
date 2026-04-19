import SwiftUI
import AppKit

/// Sheet for editing a playlist's user-facing metadata: name, custom cover
/// image, and description (capped at `Playlist.descriptionMaxLength`).
struct PlaylistEditorView: View {
    let playlistID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(PlaylistStore.self) private var playlistStore

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var artworkData: Data?
    @State private var didLoad = false
    @State private var pendingCropData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(Theme.divider)
            formBody
            Divider().foregroundStyle(Theme.divider)
            footer
        }
        .frame(width: 480, height: 420)
        .background(Theme.surface)
        .onAppear(perform: loadIfNeeded)
        .sheet(item: Binding(
            get: { pendingCropData.map { CroppingPayload(data: $0) } },
            set: { if $0 == nil { pendingCropData = nil } }
        )) { payload in
            SquareImageCropperView(sourceData: payload.data) { cropped in
                artworkData = cropped
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Edit Playlist")
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

    // MARK: - Form

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
            .help("Click to choose a custom cover image")

            if artworkData != nil {
                Button("Remove") {
                    artworkData = nil
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .buttonStyle(.plain)
            }
        }
        .frame(width: 130)
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.surfaceElevated)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Description")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(description.count)/\(Playlist.descriptionMaxLength)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(
                            description.count > Playlist.descriptionMaxLength
                                ? Theme.accent
                                : Theme.textTertiary
                        )
                }
                TextEditor(text: $description)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(height: 110)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.surfaceElevated)
                    )
                    .onChange(of: description) { _, v in
                        if v.count > Playlist.descriptionMaxLength {
                            description = String(v.prefix(Playlist.descriptionMaxLength))
                        }
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
                .keyboardShortcut(.cancelAction)

            Button("Save") { save() }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Actions

    private func loadIfNeeded() {
        guard !didLoad,
              let playlist = playlistStore.playlists.first(where: { $0.id == playlistID }) else { return }
        name = playlist.name
        description = playlist.description ?? ""
        artworkData = playlist.customArtwork
        didLoad = true
    }

    private func pickArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a playlist cover image"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        pendingCropData = data
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        playlistStore.updatePlaylistMetadata(
            id: playlistID,
            name: trimmedName,
            description: trimmedDesc.isEmpty ? nil : trimmedDesc,
            customArtwork: artworkData
        )
        dismiss()
    }
}
