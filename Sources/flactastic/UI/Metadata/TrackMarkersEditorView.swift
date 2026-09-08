import SwiftUI

/// Sheet for hand-editing chapter/track markers on a Mix Compilation track.
/// Markers are stored as an embedded CUESHEET tag (see CueSheet.swift) and
/// are only meaningful/shown for tracks with Mix Compilation enabled.
struct TrackMarkersEditorView: View {
    let track: Track

    @Environment(\.dismiss)        private var dismiss
    @Environment(\.metadataWriter) private var writer
    @Environment(PlayerState.self) private var player

    @State private var markers: [TrackMarker] = []
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    @State private var newTimestampText: String = ""
    @State private var newTitleText: String = ""

    var body: some View {
        FLSheet(title: "Chapter Markers", width: 480, height: 560) {
            body(loaded: !isLoading)
        } footer: {
            footerButtons
        }
        .alert("Save Failed", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await load() }
    }

    @ViewBuilder
    private func body(loaded: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Add timestamps to mark sections of this mix, live set, or recording.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)

            if loaded {
                if markers.isEmpty {
                    VStack {
                        Spacer()
                        Text("No markers yet")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(markers) { marker in
                            markerRow(marker)
                        }
                        .onMove { indices, newOffset in
                            markers.move(fromOffsets: indices, toOffset: newOffset)
                        }
                        .onDelete { indices in
                            markers.remove(atOffsets: indices)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                addMarkerRow
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(Theme.Spacing.xl)
    }

    private func markerRow(_ marker: TrackMarker) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(FormatUtils.formatDuration(marker.timestamp))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 56, alignment: .leading)
            TextField("Marker title", text: titleBinding(for: marker.id))
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Theme.textTertiary.opacity(0.6))
        }
    }

    private func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { markers.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let i = markers.firstIndex(where: { $0.id == id }) { markers[i].title = newValue }
            }
        )
    }

    private var addMarkerRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("mm:ss", text: $newTimestampText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.surfaceElevated)
                )
                .frame(width: 80)
            TextField("Title", text: $newTitleText)
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.surfaceElevated)
                )

            Button("At Playhead") {
                newTimestampText = FormatUtils.formatDuration(player.currentTime)
            }
            .buttonStyle(.plain)
            .font(Theme.Font.caption)
            .disabled(player.currentTrack?.id != track.id)

            Button("Add") { addMarker() }
                .buttonStyle(PillButtonStyle())
                .disabled(TrackMarker.parseUserTimestamp(newTimestampText) == nil)
        }
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

    private func addMarker() {
        guard let seconds = TrackMarker.parseUserTimestamp(newTimestampText) else { return }
        markers.append(TrackMarker(timestamp: seconds, title: newTitleText))
        markers = markers.sortedByTime()
        newTimestampText = ""
        newTitleText = ""
    }

    private func load() async {
        let loaded = (try? await writer.readMarkers(from: track)) ?? []
        await MainActor.run {
            markers = loaded
            isLoading = false
        }
    }

    private func save() {
        isSaving = true
        let payload = markers
        let snapshot = track
        Task {
            do {
                try await writer.writeMarkers(to: snapshot, markers: payload)
                await MainActor.run {
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
}
