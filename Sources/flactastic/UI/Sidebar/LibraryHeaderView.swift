import SwiftUI

struct LibraryHeaderView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let rootURL = library.rootURL {
                Text(rootURL.lastPathComponent)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            } else {
                Text("No folder selected")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.textTertiary)
            }

            statusLabel
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch library.scanState {
        case .idle:
            Text("Open a folder to get started")
        case .scanning:
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Scanning…")
            }
        case .done(let count):
            Text("\(count) track\(count == 1 ? "" : "s")")
        case .failed(let msg):
            Text("Error: \(msg)")
                .foregroundStyle(.red.opacity(0.8))
        }
    }
}
