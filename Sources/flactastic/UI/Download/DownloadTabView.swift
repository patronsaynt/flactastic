import SwiftUI

/// Full-page Download tab. Lets the user paste a streaming-service URL or run
/// a search across configured providers, queue downloads, and watch progress.
/// Credential editing lives in a sheet ("Configure providers") rather than in
/// app-wide Settings, keeping all streaming-related controls in one place.
struct DownloadTabView: View {
    @Environment(StreamerRegistry.self) private var registry
    @Environment(DownloadCoordinator.self) private var downloads

    @State private var query: String = ""
    @State private var pasteURL: String = ""
    @State private var resolved: RemoteResolveResponse?
    @State private var search: StreamerRegistry.AggregatedSearch?
    @State private var isWorking: Bool = false
    @State private var error: String?
    @State private var showProviderSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            if registry.allProviders.isEmpty {
                emptyState
            } else {
                inputs
                Divider().foregroundStyle(Theme.divider)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if let resolved { resolvedView(resolved) }
                        if let search { searchResultsView(search) }
                        if !downloads.jobs.isEmpty { jobsView }
                    }
                    .padding(.trailing, Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        .sheet(isPresented: $showProviderSheet) {
            ProviderCredentialsSheet()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Download")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                showProviderSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                    Text("Configure providers")
                }
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No streaming services configured.")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
            Text("Tap “Configure providers” above to add credentials for at least one service (Qobuz or Deezer) and unlock downloads.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Paste a track / album / playlist URL")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: Theme.Spacing.sm) {
                TextField("https://play.qobuz.com/album/...", text: $pasteURL)
                    .textFieldStyle(.roundedBorder)
                Button("Resolve") { resolve() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(pasteURL.isEmpty || isWorking)
            }

            Text("…or search the catalog")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, Theme.Spacing.sm)
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Artist, album, or track", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(performSearch)
                Button("Search") { performSearch() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(registry.allProviders, id: \.serviceID) { provider in
                    Text(provider.displayName)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.surfaceElevated))
                }
            }
            .padding(.top, 4)
        }
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
                    downloads.enqueue(a.tracks)
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
                    downloads.enqueue(p.tracks)
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 4)
            }
        case .artist(let artist, _, _):
            Text("Artist: \(artist.name)")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
            Text("Search the catalog or paste an album URL to download tracks.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func searchResultsView(_ search: StreamerRegistry.AggregatedSearch) -> some View {
        ForEach(search.perService.keys.sorted(), id: \.self) { serviceID in
            if let results = search.perService[serviceID] {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(serviceID.capitalized)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.textPrimary)
                    if !results.albums.isEmpty {
                        Text("Albums").font(Theme.Font.caption).foregroundStyle(Theme.textTertiary)
                        ForEach(results.albums) { albumRowCompact($0) }
                    }
                    if !results.tracks.isEmpty {
                        Text("Tracks").font(Theme.Font.caption).foregroundStyle(Theme.textTertiary)
                        ForEach(results.tracks) { trackRow($0, isAlbumChild: false) }
                    }
                }
            }
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

    private func albumRowCompact(_ a: RemoteAlbum) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(Theme.Font.body).foregroundStyle(Theme.textPrimary)
                Text(a.artists.map(\.name).joined(separator: ", "))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Open") { resolveAlbum(a) }
                .buttonStyle(PillButtonStyle())
        }
        .padding(.vertical, 2)
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
            Button("Download") { downloads.enqueue(t) }
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
        guard let url = URL(string: pasteURL.trimmingCharacters(in: .whitespaces)) else {
            error = "That URL doesn't look valid."
            return
        }
        resolved = nil
        search = nil
        error = nil
        isWorking = true
        Task {
            do {
                let r = try await registry.resolve(url)
                resolved = r
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            isWorking = false
        }
    }

    private func resolveAlbum(_ album: RemoteAlbum) {
        guard let provider = registry.provider(serviceID: album.serviceID),
              let url = album.url else { return }
        Task {
            isWorking = true
            do {
                let r = try await provider.resolve(url)
                resolved = r
                search = nil
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            isWorking = false
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        resolved = nil
        search = nil
        error = nil
        isWorking = true
        Task {
            let r = await registry.searchAll(q, limit: 10)
            search = r
            isWorking = false
        }
    }
}

/// Modal sheet that wraps the existing `StreamingSettingsView` in chrome
/// (title + close button). Same Keychain-backed credential editor that
/// previously lived in app Settings.
private struct ProviderCredentialsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Provider Credentials")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                StreamingSettingsView()
                    .padding(.trailing, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 600, height: 600)
        .background(Theme.surface)
    }
}
