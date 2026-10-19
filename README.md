# topside.

**A lightweight, adaptive island for macOS.**

Topside places a compact, interactive island at the top of your Mac's display. It brings together the time, battery and charging state, Nepali and Gregorian dates, Spotify playback, and small contextual interactions—without taking over the native menu bar.

> **Status:** Early macOS prototype (v0.3.0). Built for personal use; not yet a polished public release.

## Features

- **Adaptive island:** compact at rest, expanded with deliberate hover or click; adjustable height and vertical offset.
- **Clock and battery:** 12/24-hour time, charging state, Low Power Mode, and contextual battery details.
- **Dual calendars:** Gregorian (AD) and Bikram Sambat (BS) date preview; copy AD, BS, or both. No full calendar interface.
- **Spotify integration:** album artwork, play/pause, track details on hover, and previous/next controls in the pinned player. Explicit permission handling and clear error states.
- **Subtle microinteractions:** hover dwell, leave grace, charging feedback, and audio-output awareness.
- **System-aware behavior:** fullscreen auto-hide, top-edge reveal, menu-tracking suppression, sleep/wake recovery, and active-display placement.
- **Keyboard and accessibility:** explicit pinning for keyboard interaction, Escape to dismiss, accessibility labels, and configurable show/hide shortcuts.
- **Native and local-first:** Swift, AppKit/SwiftUI, IOKit; no mandatory account, subscription, or cloud backend. Spotify artwork may be downloaded from Spotify's CDN.

## Requirements

- macOS 13 or newer
- Apple Silicon or compatible macOS Swift build environment
- Xcode Command Line Tools / Swift toolchain (Swift tools version 5.9 or later)
- Spotify desktop app for music controls (optional)

## Build and run

Clone the repository and run from its root:

```bash
git clone https://github.com/PrijeshBikramShahi/topside.git
cd topside
swift test
bash build_app.sh
open build/Topside.app
```

`build_app.sh` builds a release binary and packages an app in `build/Topside.app`. It prefers an available Developer ID Application signing identity, falls back to an Apple Development identity, and finally to ad-hoc signing. A stable signing identity is recommended for macOS Automation permissions to persist between builds.

The app runs as a menu-bar/accessory application (no Dock icon). Use the menu-bar capsule icon to open Settings, hide/show the island, or quit. Launching the app again while it is already running opens Settings.

**Logs:** `~/Library/Logs/Topside.log`  
**Bundle ID:** `com.prizesh.topside`

## How it works

| Interaction | Result |
| --- | --- |
| Resting island | Clock, relevant battery state, compact Spotify controls |
| Hover over a section | Brief contextual preview after a short dwell |
| Click a section | Pin its expanded content |
| Click outside or press Escape | Dismiss pinned content |
| Click a date action | Copy AD, BS, or both dates |
| Enter fullscreen | Hide island; reveal temporarily at the top edge |
| Use the menu-bar icon | Open settings, visibility controls, or quit |

Spotify control requires permission from macOS Automation. Topside does not silently launch Spotify when checking playback. Some transport actions depend on the installed Spotify version and account behavior.

## Project structure

```text
Sources/
  Topside/          # App, island UI, system integration, Spotify services
  TopsideCore/      # Pure logic for dates, battery, layout, interaction and playback states
Tests/
  TopsideCoreTests/ # Core unit tests
Package.swift       # Swift Package Manager manifest
build_app.sh         # App bundle build and signing script
THIRD_PARTY_NOTICES.md
```

## Current verification and limitations

The project's previous verification record (19 October 2026) reports successful debug/release builds and **84 passing core tests**, with a small set of on-device island interactions checked manually. Treat those numbers as a development snapshot, not a promise about every machine or build.

Areas that still need full manual validation include Spotify transport/permission flows, external-display transitions, hardware power-state transitions, and a complete VoiceOver audit. BS conversion covers **BS 2070–2099**; dates after 2084 use cross-checked projected calendar data and **should not be used for legal or official purposes**.

Topside is currently a **virtual island**, not a complete replacement for the macOS menu bar. Expanded menu-bar functionality is a separate planned direction.

## Development

Run core tests:

```bash
swift test
```

Create a fresh local build:

```bash
bash build_app.sh
open build/Topside.app
```

SwiftPM's `.build/` directory and the packaged `build/` app are generated artifacts; they should not be committed. See `.gitignore`.

## Privacy

Topside's core clock, battery, date, and display behaviors run locally. Spotify integration uses local AppleScript automation, with user-controlled macOS permissions. Album art may be fetched from Spotify-hosted URLs. The development log records state changes/error codes rather than track titles or artists.

## Third-party notices

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution and license notices concerning Bikram Sambat calendar data.

## License

**No project-wide license has been declared yet.** Until a license is added, normal copyright restrictions apply. Third-party notices do not, by themselves, license the whole project.
