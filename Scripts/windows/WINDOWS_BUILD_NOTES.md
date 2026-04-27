# Windows Build Notes (Future Work)

FLACtastic is currently a native macOS-only app written in Swift/SwiftUI.
A Windows build is **not yet implemented**. This document captures the
expected approach so the release infrastructure can be extended when the
Windows port is ready.

## Why Windows is non-trivial

The current codebase depends on Apple-only frameworks:

- **SwiftUI** — UI; no Windows equivalent in the Swift toolchain
- **AppKit** — windowing, menu bar, NSEvent monitoring
- **AVFoundation** — audio playback engine

A Windows port requires either:

1. **Rewriting the UI layer** in a cross-platform framework
   (e.g. SwiftCrossUI, Skia + custom layer, or porting to a different
   stack entirely like Rust + egui or C++ + Qt)
2. **Or using a different language** for Windows (C# / WPF, Rust + Tauri,
   etc.) and sharing only the audio/metadata logic via a common library.

Given the scope, treat the Windows port as a separate project that *uses*
this DMG release infrastructure as a template, not a quick add-on.

## When the time comes — proposed structure

```
Scripts/
├── build-release.sh        # already detects platform via uname -s
├── macos/
│   └── …
└── windows/
    ├── package-windows.ps1   # build .exe + assemble portable folder
    ├── create-msi.ps1        # WiX-based installer
    └── sign-windows.ps1      # signtool.exe code signing
```

`build-release.sh` already short-circuits with a clear error on
Windows/Linux. When ready, replace that error with an invocation of
`Scripts/windows/package-windows.ps1` (via `pwsh`).

## Tooling to evaluate when starting

- **WiX Toolset** — for .msi creation (industry standard, free)
- **Inno Setup** — simpler .exe-only installers
- **signtool.exe** — code signing (requires an EV or OV cert from a CA
  like DigiCert or Sectigo; ~$200–$400/year)
- **GitHub Actions windows-latest runners** — for automated builds

## Versioning

`version.txt` at the project root is already platform-agnostic. The
Windows build should read from the same file so the macOS DMG and
Windows MSI ship the same version number.

## Distribution

GitHub Releases is the simplest cross-platform host: upload both the
`.dmg` and `.msi` to the same release tag.
