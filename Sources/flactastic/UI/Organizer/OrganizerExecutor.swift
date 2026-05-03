import Foundation

/// Performs the planned moves on disk. Operations are executed sequentially so
/// `(1)` collision suffixes are deterministic and so we can prune empty source
/// directories bottom-up after the move pass without racing.
actor OrganizerExecutor {
    enum Phase: Sendable {
        case moving
        case cleaningUp
        case validating
    }

    struct Progress: Sendable {
        let phase: Phase
        let completed: Int
        let total: Int
    }

    struct Result {
        var moved: [(trackID: UUID, newURL: URL)] = []
        var skipped: Int = 0
        var failed: [(URL, String)] = []
        /// Files we expected to find at their destination but didn't after the
        /// move pass. Surfaces as a hard error in the UI so the user knows
        /// something went wrong before they trust the result.
        var lostFiles: [URL] = []
    }

    func run(
        operations: [OrganizerOperation],
        rootURL: URL,
        deleteEmptyOriginals: Bool,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async -> Result {
        let fm = FileManager.default
        var result = Result()
        var sourceParents: Set<URL> = []
        let total = operations.count

        onProgress(Progress(phase: .moving, completed: 0, total: total))

        for (i, op) in operations.enumerated() {
            switch op.status {
            case .unchanged:
                result.skipped += 1
                onProgress(Progress(phase: .moving, completed: i + 1, total: total))
                continue
            case .move, .conflict:
                break
            }

            do {
                try fm.createDirectory(at: op.destinationFolder, withIntermediateDirectories: true)
                let finalDest: URL
                if fm.fileExists(atPath: op.destinationURL.path) {
                    finalDest = ImportCopy.uniqueDestination(
                        for: op.destinationURL.lastPathComponent,
                        in: op.destinationFolder
                    )
                } else {
                    finalDest = op.destinationURL
                }
                try fm.moveItem(at: op.sourceURL, to: finalDest)
                sourceParents.insert(op.sourceURL.deletingLastPathComponent())
                result.moved.append((op.track.id, finalDest))
            } catch {
                result.failed.append((op.sourceURL, error.localizedDescription))
            }
            onProgress(Progress(phase: .moving, completed: i + 1, total: total))
        }

        if deleteEmptyOriginals {
            onProgress(Progress(phase: .cleaningUp, completed: 0, total: sourceParents.count))
            pruneAudioFreeDirectories(startingFrom: sourceParents,
                                       stoppingAt: rootURL,
                                       onProgress: onProgress)
        }

        // Validation pass: every move we recorded as successful must exist at
        // its destination. If not, mark it as lost.
        let movedSnapshot = result.moved
        onProgress(Progress(phase: .validating, completed: 0, total: movedSnapshot.count))
        for (i, entry) in movedSnapshot.enumerated() {
            if !fm.fileExists(atPath: entry.newURL.path) {
                result.lostFiles.append(entry.newURL)
            }
            onProgress(Progress(phase: .validating, completed: i + 1, total: movedSnapshot.count))
        }

        return result
    }

    /// Walks up from each leaf parent toward `rootURL`. A directory is removed
    /// (recursively) if it contains no audio files anywhere in its subtree —
    /// this scoops up leftover cover art, `.DS_Store`, log files, etc. that
    /// sat alongside the audio we just moved out. Stops at (but never deletes)
    /// `rootURL` itself. Only directories that previously contained audio
    /// (i.e. ancestors of a moved source) are eligible, so unrelated folders
    /// are never touched.
    private func pruneAudioFreeDirectories(
        startingFrom leaves: Set<URL>,
        stoppingAt rootURL: URL,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) {
        let fm = FileManager.default
        let root = rootURL.standardizedFileURL.path
        let ordered = leaves.sorted { $0.pathComponents.count > $1.pathComponents.count }
        var visited: Set<String> = []
        let total = ordered.count
        for (i, leaf) in ordered.enumerated() {
            var dir = leaf.standardizedFileURL
            while dir.path != root, dir.path.hasPrefix(root), !visited.contains(dir.path) {
                visited.insert(dir.path)
                guard fm.fileExists(atPath: dir.path) else {
                    dir.deleteLastPathComponent()
                    continue
                }
                if directoryContainsAudio(dir) {
                    break
                }
                try? fm.removeItem(at: dir)
                dir.deleteLastPathComponent()
            }
            onProgress(Progress(phase: .cleaningUp, completed: i + 1, total: total))
        }
    }

    /// True if `dir` contains any audio file recursively. Uses the shared
    /// `AudioFileFormat.classify` so the definition of "audio" matches the
    /// rest of the app.
    private func directoryContainsAudio(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        for case let url as URL in enumerator {
            if AudioFileFormat.classify(url) != nil {
                return true
            }
        }
        return false
    }
}
