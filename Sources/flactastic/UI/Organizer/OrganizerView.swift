import SwiftUI

/// 5th tab: lets the user reshape their source folder by defining a folder
/// hierarchy and filename template, previewing the resulting moves, and
/// applying them. Designed to feel approachable: token chips replace
/// memorisation, every template has a live example, and Apply is gated behind
/// a confirmation because the operation moves files in place.
struct OrganizerView: View {
    @Environment(LibraryStore.self) private var library
    @State private var store = OrganizerProfilesStore()
    @State private var model = OrganizerModel()
    @State private var showApplyConfirm = false
    @State private var showRename = false
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            profileBar
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)

            Divider().background(Theme.divider)

            HStack(alignment: .top, spacing: 0) {
                configurationColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Theme.Spacing.xl)

                Divider().background(Theme.divider)

                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Theme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .overlay {
            if model.isApplying {
                applyOverlay
            }
        }
        .confirmationDialog(
            "Apply organization?",
            isPresented: $showApplyConfirm,
            titleVisibility: .visible
        ) {
            Button("Move \(model.moveCount) files", role: .destructive) {
                Task { await model.apply(library: library, profile: store.selected) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will move files in place inside your source folder. \(model.conflictCount) conflict\(model.conflictCount == 1 ? "" : "s") will be resolved by appending a numeric suffix.")
        }
        .sheet(isPresented: $showRename) {
            renameSheet
        }
    }

    // MARK: - Profile bar

    private var profileBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 18))
                .foregroundStyle(Theme.textSecondary)

            Text("Organizer")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Menu {
                ForEach(store.profiles) { profile in
                    Button {
                        store.selectedID = profile.id
                        model.markStale()
                    } label: {
                        if profile.id == store.selectedID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
                Divider()
                Button("New from Preset…") { } // anchor; presets below
                ForEach(OrganizerProfile.presets) { preset in
                    Button("New: \(preset.name)") {
                        var fresh = preset
                        fresh.id = UUID()
                        store.add(fresh)
                        model.markStale()
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(store.selected.name)
                        .font(Theme.Font.bodyMedium)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Capsule().fill(Theme.surface))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            iconButton("pencil", help: "Rename profile") {
                renameDraft = store.selected.name
                showRename = true
            }
            iconButton("plus.square.on.square", help: "Duplicate profile") {
                store.duplicateSelected()
                model.markStale()
            }
            iconButton("trash", help: "Delete profile") {
                store.removeSelected()
                model.markStale()
            }
            .disabled(store.profiles.count <= 1)
        }
    }

    private func iconButton(_ system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Rename profile")
                .font(Theme.Font.headline)
            TextField("Profile name", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showRename = false }
                Button("Save") {
                    var s = store.selected
                    s.name = renameDraft.trimmingCharacters(in: .whitespaces)
                    if !s.name.isEmpty { store.selected = s }
                    showRename = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360)
    }

    // MARK: - Configuration column

    private var configurationColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                sectionHeader("Folder hierarchy", subtitle: "Files are placed in nested folders, top to bottom.")

                if store.selected.levels.isEmpty {
                    emptyHierarchyHint
                } else {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(store.selected.levels) { level in
                            hierarchyRow(level)
                        }
                    }
                }

                Button {
                    var s = store.selected
                    s.levels.append(HierarchyLevel(groupBy: .album))
                    store.selected = s
                    model.markStale()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add level")
                    }
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)

                Divider().background(Theme.divider).padding(.vertical, Theme.Spacing.sm)

                sectionHeader("File name", subtitle: "How each track file is named within its folder.")
                templateField(
                    template: Binding(
                        get: { store.selected.fileTemplate },
                        set: { newValue in
                            var s = store.selected
                            s.fileTemplate = newValue
                            store.selected = s
                            model.markStale()
                        }
                    ),
                    fallback: "Untitled"
                )

                Divider().background(Theme.divider).padding(.vertical, Theme.Spacing.sm)

                primaryArtistToggle

                deleteEmptyOriginalsToggle

                Divider().background(Theme.divider).padding(.vertical, Theme.Spacing.sm)

                tokenReference
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var emptyHierarchyHint: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Add a grouping level to begin.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(OrganizerProfile.presets) { preset in
                    Button(preset.name) {
                        var s = store.selected
                        s.levels = preset.levels.map {
                            HierarchyLevel(id: UUID(), groupBy: $0.groupBy, nameTemplate: $0.nameTemplate)
                        }
                        s.fileTemplate = preset.fileTemplate
                        store.selected = s
                        model.markStale()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Capsule().fill(Theme.surface))
                    .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.surface.opacity(0.5)))
    }

    private func hierarchyRow(_ level: HierarchyLevel) -> some View {
        let idx = store.selected.levels.firstIndex(of: level) ?? 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(idx + 1)")
                    .font(Theme.Font.captionMono)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 18, alignment: .center)

                Menu {
                    ForEach(GroupingField.allCases) { field in
                        Button(field.displayName) {
                            var s = store.selected
                            if let i = s.levels.firstIndex(where: { $0.id == level.id }) {
                                let oldDefault = s.levels[i].groupBy.defaultTemplate
                                s.levels[i].groupBy = field
                                if s.levels[i].nameTemplate == oldDefault {
                                    s.levels[i].nameTemplate = field.defaultTemplate
                                }
                            }
                            store.selected = s
                            model.markStale()
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(level.groupBy.displayName)
                            .font(Theme.Font.bodyMedium)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.surfaceElevated))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                templateField(
                    template: Binding(
                        get: { level.nameTemplate },
                        set: { newValue in
                            var s = store.selected
                            if let i = s.levels.firstIndex(where: { $0.id == level.id }) {
                                s.levels[i].nameTemplate = newValue
                            }
                            store.selected = s
                            model.markStale()
                        }
                    ),
                    fallback: level.groupBy.displayName,
                    inline: true
                )

                Spacer(minLength: 0)

                Button {
                    moveLevel(level, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(idx == 0)

                Button {
                    moveLevel(level, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(idx == store.selected.levels.count - 1)

                Button {
                    var s = store.selected
                    s.levels.removeAll { $0.id == level.id }
                    store.selected = s
                    model.markStale()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.surface))
    }

    private func moveLevel(_ level: HierarchyLevel, by delta: Int) {
        var s = store.selected
        guard let i = s.levels.firstIndex(where: { $0.id == level.id }) else { return }
        let j = i + delta
        guard j >= 0 && j < s.levels.count else { return }
        s.levels.swapAt(i, j)
        store.selected = s
        model.markStale()
    }

    private func templateField(template: Binding<String>, fallback: String, inline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            TextField("Template", text: template)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.background))

            if !inline {
                tokenChips(insertInto: template)
            }

            if let sample = examplePreview(template: template.wrappedValue, fallback: fallback) {
                Text("Example: \(sample)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func tokenChips(insertInto template: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(OrganizerTemplate.allTokens) { token in
                    Button {
                        template.wrappedValue += token.placeholder
                        model.markStale()
                    } label: {
                        Text(token.placeholder)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .help(token.description)
                }
            }
        }
    }

    private var tokenReference: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Tokens")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
            ForEach(OrganizerTemplate.allTokens) { token in
                HStack(spacing: Theme.Spacing.sm) {
                    Text(token.placeholder)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 110, alignment: .leading)
                    Text(token.description)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func examplePreview(template: String, fallback: String) -> String? {
        guard let track = library.tracks.first else { return nil }
        return OrganizerTemplate.render(template, for: track, fallback: fallback,
                                        primaryArtistOnly: store.selected.usePrimaryArtistOnly)
    }

    private var primaryArtistToggle: some View {
        let binding = Binding(
            get: { store.selected.usePrimaryArtistOnly },
            set: { newValue in
                var s = store.selected
                s.usePrimaryArtistOnly = newValue
                store.selected = s
                model.markStale()
            }
        )
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Toggle(isOn: binding) {
                Text("Use primary artist only")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            Text("For tracks credited to multiple artists (\u{201C}A & B\u{201D}, \u{201C}A feat. B\u{201D}, \u{201C}A; B\u{201D}), file under just the first.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var deleteEmptyOriginalsToggle: some View {
        let binding = Binding(
            get: { store.selected.deleteEmptyOriginals },
            set: { newValue in
                var s = store.selected
                s.deleteEmptyOriginals = newValue
                store.selected = s
            }
        )
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Toggle(isOn: binding) {
                Text("Delete empty original folders")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            Text("After moves complete, remove any source folders that are now empty (walks up to your library root).")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Preview column

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                sectionHeader("Preview", subtitle: previewSubtitle)
                Spacer()
                Button {
                    model.generatePreview(profile: store.selected, tracks: library.tracks, rootURL: library.rootURL)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                        Text(model.operations.isEmpty ? "Generate Preview" : "Refresh")
                    }
                    .font(Theme.Font.bodyMedium)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Capsule().fill(Theme.surfaceElevated))
                    .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
            }

            if let err = model.lastError {
                inlineNotice(text: err, color: Theme.qualityLow)
            } else if let msg = model.lastResultMessage, model.operations.isEmpty {
                inlineNotice(text: msg, color: Theme.qualityCD)
            }

            if model.isPreviewStale && !model.operations.isEmpty {
                inlineNotice(text: "Configuration changed — refresh to update the preview.", color: Theme.qualityMid)
            }

            if model.operations.isEmpty {
                emptyPreviewState
            } else {
                previewList
            }

            Spacer(minLength: 0)

            HStack {
                if model.conflictCount > 0 {
                    Label("\(model.conflictCount) conflict\(model.conflictCount == 1 ? "" : "s")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.qualityMid)
                }
                Spacer()
                Button {
                    showApplyConfirm = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if model.isApplying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(model.isApplying ? "Applying…" : "Apply")
                    }
                    .font(Theme.Font.bodyMedium)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(applyEnabled ? Theme.accent : Theme.surfaceElevated))
                    .foregroundStyle(applyEnabled ? Theme.background : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!applyEnabled)
            }
        }
    }

    private var applyEnabled: Bool {
        !model.isApplying
            && !model.isPreviewStale
            && model.moveCount > 0
            && library.rootURL != nil
    }

    private var previewSubtitle: String {
        if model.operations.isEmpty {
            return "Generate a preview to see what would change."
        }
        return "\(model.moveCount) to move · \(model.unchangedCount) unchanged · \(model.conflictCount) conflicts"
    }

    private var emptyPreviewState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text("No preview yet")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.textSecondary)
            if library.rootURL == nil {
                Text("Choose a source folder in Settings, then come back.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text("Click Generate Preview to see how \(library.tracks.count) files would be organized.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.surface.opacity(0.5)))
    }

    private var previewList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedPreview, id: \.folder) { group in
                    Section {
                        ForEach(group.ops) { op in
                            previewRow(op)
                        }
                    } header: {
                        Text(displayPath(group.folder))
                            .font(Theme.Font.captionMono)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceElevated)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.surface.opacity(0.5)))
    }

    private struct PreviewGroup {
        let folder: URL
        let ops: [OrganizerOperation]
    }

    private var groupedPreview: [PreviewGroup] {
        let grouped = Dictionary(grouping: model.operations) { $0.destinationFolder }
        return grouped
            .map { PreviewGroup(folder: $0.key, ops: $0.value) }
            .sorted { $0.folder.path.localizedStandardCompare($1.folder.path) == .orderedAscending }
    }

    private func displayPath(_ url: URL) -> String {
        guard let root = library.rootURL else { return url.path }
        let rootPath = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        if p.hasPrefix(rootPath) {
            let rel = String(p.dropFirst(rootPath.count))
            return rel.isEmpty ? "/" : rel
        }
        return p
    }

    private func previewRow(_ op: OrganizerOperation) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: statusIcon(op.status))
                .font(.system(size: 11))
                .foregroundStyle(statusColor(op.status))
                .frame(width: 16)
            Text(op.destinationURL.lastPathComponent)
                .font(Theme.Font.body)
                .foregroundStyle(textColor(op.status))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(op.sourceURL.lastPathComponent)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .help("From: \(op.sourceURL.path)\nTo: \(op.destinationURL.path)")
    }

    private func statusIcon(_ status: OrganizerOperation.Status) -> String {
        switch status {
        case .move: return "arrow.right.circle"
        case .unchanged: return "equal.circle"
        case .conflict: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: OrganizerOperation.Status) -> Color {
        switch status {
        case .move: return Theme.textSecondary
        case .unchanged: return Theme.textTertiary
        case .conflict: return Theme.qualityMid
        }
    }

    private func textColor(_ status: OrganizerOperation.Status) -> Color {
        switch status {
        case .move: return Theme.textPrimary
        case .unchanged: return Theme.textTertiary
        case .conflict: return Theme.qualityMid
        }
    }

    private var applyOverlay: some View {
        ZStack {
            Theme.background.opacity(0.75).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                ProgressView(value: model.applyProgress ?? 0)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 320)
                Text(model.applyPhaseLabel ?? "Working…")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("Don't quit the app until this finishes.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Spacing.xl)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.surfaceElevated))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
        .transition(.opacity)
    }

    private func inlineNotice(text: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(color.opacity(0.12)))
    }
}
