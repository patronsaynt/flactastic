import SwiftUI

/// Full-page Download tab. The user pastes a streaming-service URL and
/// presses return; the registry routes it to the appropriate provider
/// (native Qobuz/Deezer when configured, Lucida otherwise) and we show the
/// resolved track/album plus any in-flight downloads.
struct DownloadTabView: View {
    @Environment(StreamerRegistry.self) private var registry
    @Environment(DownloadCoordinator.self) private var downloads

    @State private var pasteURL: String = ""
    @State private var resolved: RemoteResolveResponse?
    @State private var isWorking: Bool = false
    @State private var error: String?
    /// Per-paste download knobs (region, format, metadata, compat). Reset to
    /// defaults each time the user pastes a fresh URL. Applied to every
    /// track that gets enqueued from the resolved view below.
    @State private var options: LucidaOptions = .default

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Download")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.textPrimary)
                Text("Paste a link from Spotify, Tidal, Qobuz, Amazon Music, or SoundCloud below")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            TextField("Paste a track, album, or playlist URL", text: $pasteURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)
                .onSubmit(resolve)

            Divider().foregroundStyle(Theme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let resolved {
                        resolvedView(resolved)
                        optionsPanel
                    }
                    if !downloads.jobs.isEmpty { jobsView }
                }
                .padding(.trailing, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error {
                Text(error)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    // MARK: - Sections

    /// Mirrors the controls on lucida.to's track page. Defaults preserve
    /// the highest-quality original (no transcode, embedded metadata).
    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Options")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
            Picker("Convert to", selection: $options.format) {
                ForEach(LucidaOptions.Format.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Text("Region")
                    .foregroundStyle(Theme.textSecondary)
                TextField("auto or country code", text: $options.region)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            Toggle("Embed metadata + cover art", isOn: $options.addMetadata)
            Toggle("Player compatibility (smaller cover, ID3v2.3)",
                   isOn: $options.compatibility)
        }
        .padding(Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceElevated))
    }

    @ViewBuilder
    private func resolvedView(_ resolved: RemoteResolveResponse) -> some View {
        switch resolved {
        case .track(let t):
            trackRow(t, isAlbumChild: false)
        case .album(let a):
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                albumHeader(a)
                ForEach(a.tracks) { trackRow($0, isAlbumChild: true) }
                Button("Download All Tracks") {
                    enqueueWithOptions(a.tracks)
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 4)
            }
        case .playlist(let p):
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(p.title).font(Theme.Font.bodyMedium).foregroundStyle(Theme.textPrimary)
                if let creator = p.creator {
                    Text("by \(creator)").font(Theme.Font.caption).foregroundStyle(Theme.textSecondary)
                }
                ForEach(p.tracks) { trackRow($0, isAlbumChild: false) }
                Button("Download All Tracks") {
                    enqueueWithOptions(p.tracks)
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 4)
            }
        case .artist(let artist, _, _):
            Text("Artist: \(artist.name)")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
            Text("Paste a track or album URL to download.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func albumHeader(_ a: RemoteAlbum) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(a.title).font(Theme.Font.bodyMedium).foregroundStyle(Theme.textPrimary)
            Text(a.artists.map(\.name).joined(separator: ", "))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func trackRow(_ t: RemoteTrack, isAlbumChild: Bool) -> some View {
        HStack {
            if isAlbumChild, let n = t.trackNumber {
                Text(String(format: "%02d", n))
                    .font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(Theme.Font.body).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Text(t.artists.map(\.name).joined(separator: ", "))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if t.isLossless {
                        Text("FLAC")
                            .font(Theme.Font.caption)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Theme.accent.opacity(0.2)))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("Lossy")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Spacer()
            Button("Download") { enqueueWithOptions([t]) }
                .buttonStyle(PillButtonStyle())
        }
        .padding(.vertical, 2)
    }

    private var jobsView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Downloads")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Clear Completed") { downloads.clearCompleted() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(downloads.jobs) { job in
                HStack {
                    Text(job.track.title)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(jobStatusLabel(job.status))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func jobStatusLabel(_ status: DownloadCoordinator.JobStatus) -> String {
        switch status {
        case .queued: return "Queued"
        case .downloading(let r, let t):
            if let t, t > 0 {
                let pct = Int((Double(r) / Double(t)) * 100)
                return "Downloading… \(pct)%"
            }
            return "Downloading… \(r / 1024) KB"
        case .tagging:    return "Tagging…"
        case .finishing:  return "Moving into library…"
        case .completed:  return "Done"
        case .failed(let m): return "Failed — \(m)"
        }
    }

    // MARK: - Actions

    private func resolve() {
        let trimmed = pasteURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: trimmed) else {
            error = "That URL doesn't look valid."
            return
        }
        resolved = nil
        error = nil
        isWorking = true
        // Fresh paste — reset the options panel so the previous track's
        // choices don't silently leak into a new resolution.
        options = .default
        Task {
            do {
                resolved = try await registry.resolve(url)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            isWorking = false
        }
    }

    /// Stamp the current options on each track via the Lucida provider, then
    /// hand the tracks to the coordinator. The provider drains its options
    /// dictionary as `getStream` runs, so old entries don't pile up.
    private func enqueueWithOptions(_ tracks: [RemoteTrack]) {
        if let lucida = registry.provider(serviceID: "lucida") as? LucidaWebProvider {
            for t in tracks { lucida.setOptions(options, for: t) }
        }
        downloads.enqueue(tracks)
    }
}
