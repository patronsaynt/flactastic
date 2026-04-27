# FLACtastic Beta Testing Guide

Thanks for helping test FLACtastic! This guide covers installation and what to look for while testing.

## System requirements

- **macOS 14 (Sonoma) or later**
- **Apple Silicon Mac** (M1, M2, M3, M4 — this beta is arm64 only)
- ~50 MB free disk space

## Installation

1. Download `FLACtastic-<version>.dmg`.
2. Double-click the DMG to mount it.
3. Drag **FLACtastic.app** onto the **Applications** shortcut in the DMG window.
4. Eject the DMG (drag it to the Trash or right-click → Eject).

### First launch — bypassing Gatekeeper

This beta is **ad-hoc signed** (not notarized by Apple), so macOS will block it on first launch with:

> "FLACtastic" cannot be opened because the developer cannot be verified.

**To bypass this — once per install:**

1. Open the **Applications** folder in Finder.
2. **Right-click** (or Control-click) on **FLACtastic.app**.
3. Choose **Open** from the context menu.
4. Click **Open** in the dialog that appears.

After that first launch, you can open the app normally (Spotlight, dock, double-click).

If macOS Sequoia (15.x) is more restrictive, you may need to go to:
**System Settings → Privacy & Security**, scroll to the bottom, and click
**Open Anyway** next to the FLACtastic warning.

## What to test

### Core flows
- [ ] App launches and shows the onboarding screen on first run
- [ ] Selecting a music folder scans and displays your library
- [ ] Album art appears for tracks that have embedded artwork
- [ ] Tracks play without distortion or skipping
- [ ] Play / Pause via spacebar works (even when other controls have focus)
- [ ] Cmd+← / Cmd+→ skips between tracks
- [ ] Cmd+↑ / Cmd+↓ adjusts volume
- [ ] Cmd+R refreshes the library

### Library features
- [ ] Importing a single track works (Collection → Import Track…)
- [ ] Importing an album works (Collection → Import Album…)
- [ ] Importing files as a playlist works (Collection → Import Files as Playlist…)
- [ ] Editing track metadata saves correctly and persists across restarts

### UI / UX
- [ ] Light/dark mode toggle works (Settings)
- [ ] UI scaling works at different settings
- [ ] Menu bar mini-player appears when enabled and a track is playing
- [ ] Window resizing behaves correctly down to the 1000×650 minimum

### File format support
- [ ] FLAC files
- [ ] MP3 files
- [ ] M4A / AAC files
- [ ] WAV files

## Reporting issues

When reporting a bug, please include:

1. **macOS version** (Apple menu → About This Mac)
2. **Mac model** (e.g., MacBook Pro M2, Mac mini M1)
3. **FLACtastic version** (from the DMG filename, or About panel)
4. **Steps to reproduce** the issue
5. **What you expected** vs **what actually happened**
6. A **screenshot** or **screen recording** if it's a visual issue

Crash logs (if applicable) live at:
`~/Library/Logs/DiagnosticReports/flactastic-*.ips`

## Uninstalling

1. Quit FLACtastic.
2. Drag **FLACtastic.app** from /Applications to the Trash.
3. (Optional) To remove preferences and library data:
   ```
   rm -rf ~/Library/Application\ Support/flactastic
   rm -rf ~/Library/Preferences/com.flactastic.app.plist
   ```

## Known limitations of this beta

- **Apple Silicon only** — no Intel Mac build yet.
- **Not notarized** — Gatekeeper will require the right-click → Open workaround on first launch.
- **No auto-updates** — install future betas manually.
