import Foundation

/// One row of the Organizer's preview column: either a destination folder or a
/// file that lands inside it. Rows are pre-flattened with an indent depth so the
/// column renders them in a single lazy stack.
struct OrganizerPreviewRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder
        case file
    }

    let id: String
    let depth: Int
    let label: String
    let kind: Kind
    /// Format tag ("FLAC", "MP3", …) shown as a badge on file rows.
    let badge: String?
    let isConflict: Bool
    let isUnchanged: Bool
}

enum OrganizerPreviewTree {
    /// Flattens a move plan into folder/file rows in path order.
    ///
    /// Operations arrive from `OrganizerPlanner` already sorted by destination
    /// path, so a running comparison against the previous path is enough to
    /// emit each folder exactly once. Only the first `limit` rows are built —
    /// the preview is a sample, not a file manager — and the number of tracks
    /// that fell outside the sample is returned so the UI can say how many more
    /// are organized the same way.
    static func rows(
        for operations: [OrganizerOperation],
        rootURL: URL?,
        limit: Int = 300
    ) -> (rows: [OrganizerPreviewRow], hiddenTrackCount: Int) {
        guard let rootURL else { return ([], 0) }
        let rootComponents = rootURL.standardizedFileURL.pathComponents

        var rows: [OrganizerPreviewRow] = []
        var previousFolders: [String] = []
        var shownTracks = 0

        for op in operations {
            guard rows.count < limit else { break }

            var components = op.destinationURL.standardizedFileURL.pathComponents
            if components.count >= rootComponents.count,
               Array(components.prefix(rootComponents.count)) == rootComponents {
                components.removeFirst(rootComponents.count)
            }
            guard let filename = components.popLast() else { continue }

            var shared = 0
            while shared < min(components.count, previousFolders.count),
                  components[shared] == previousFolders[shared] {
                shared += 1
            }
            for depth in shared..<components.count {
                rows.append(OrganizerPreviewRow(
                    id: "folder/" + components[0...depth].joined(separator: "/"),
                    depth: depth,
                    label: components[depth],
                    kind: .folder,
                    badge: nil,
                    isConflict: false,
                    isUnchanged: false
                ))
            }
            previousFolders = components

            let isConflict: Bool
            if case .conflict = op.status { isConflict = true } else { isConflict = false }
            let isUnchanged: Bool
            if case .unchanged = op.status { isUnchanged = true } else { isUnchanged = false }

            rows.append(OrganizerPreviewRow(
                id: "file/" + op.id.uuidString,
                depth: components.count,
                label: filename,
                kind: .file,
                badge: op.track.fileFormat.displayName,
                isConflict: isConflict,
                isUnchanged: isUnchanged
            ))
            shownTracks += 1
        }

        return (rows, max(0, operations.count - shownTracks))
    }
}
