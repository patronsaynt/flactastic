import SwiftUI

struct FolderPickerButton: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Settings.self) private var settings

    var body: some View {
        Button {
            openFolder()
        } label: {
            Image(systemName: "folder.badge.plus")
        }
        .help("Open music folder")
    }

    @MainActor
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose your music folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.lastRootPath = url.path
            library.openFolder(url)
        }
    }
}
