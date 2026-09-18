# DynamicNotch

Make your MacBook's notch actually useful. DynamicNotch turns the notch into a live system dashboard — music controls, fan speeds, CPU stats, audio visualization, and smart HUD replacements, all in the space that was doing nothing.

---

## Features

- **Dynamic notch sizing** — expands and contracts based on what's happening on screen
- **Responsive spectrogram** — real-time audio visualizer driven by live capture
- **Fan & thermal monitoring** — live fan speed and CPU temperature
- **CPU usage** — at a glance, always visible
- **Caffeine** — prevent sleep directly from the notch
- **Custom system HUDs** — replaces macOS volume, brightness, and keyboard backlight overlays
- **Music playback** — album art, controls, and now-playing info
- **Calendar & Reminders** — upcoming events in the notch
- **File shelf** — drag files in, AirDrop them out
- **Mirror** — quick webcam view
- **Battery indicator** — charging status and percentage
- **Gesture controls** — swipe to open/close

---

## Requirements

- macOS **15 Sequoia** or later
- Any Mac — DynamicNotch draws its own custom notch, so a physical notch display isn't required

---

## Versioning

DynamicNotch's version number tracks the macOS version it's built and optimised for, not an independent app version:

- **Major** (`27` in `27.1.2`) — the macOS major version the release targets (e.g. macOS 27). This only changes when Apple ships a new macOS major version.
- **Minor** (`.1`) — a new feature has landed.
- **Patch** (`.2`) — a bug fix for the current minor.

For example, `27.1` means "the first feature release built and optimised for macOS 27." The patch level is only shown when a patch actually exists.

Because the minimum deployment target is macOS 15, **any version still runs on macOS 15 and up** — a release numbered `27.5` isn't macOS-27-only, it's just built and tuned against macOS 27, while remaining fully compatible with older supported macOS versions down to 15.

---

## Installation

### Option 1: Download and Install Manually

1. Download the latest **DynamicNotch.dmg** from the [Releases](https://github.com/Hitjack007/DynamicNotch/releases/latest) page
2. Open the DMG and drag **DynamicNotch** to your Applications folder
3. Before opening, run this once in Terminal to clear the macOS security warning:
   ```bash
   xattr -dr com.apple.quarantine /Applications/DynamicNotch.app
   ```
4. Open the app — your notch is now alive

### Option 2: Install via Homebrew

You can also install using [Homebrew](https://brew.sh). The Homebrew installation automatically bypasses the macOS security warning described above.

```bash
brew install --cask hitjack007/dynamicnotch/dynamicnotch
```

---

## Building from Source

For developers who want to build it themselves:

### Prerequisites
- macOS 15 or later
- Xcode 26 or later

### Steps

```bash
git clone https://github.com/Hitjack007/DynamicNotch.git
cd DynamicNotch
open dynamicNotch.xcodeproj
```

In Xcode, set your own development team under **Signing & Capabilities** for both `dynamicNotch` and `BoringNotchXPCHelper`, then press **Cmd + R**.

---

## Credits

DynamicNotch is a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch) by [TheBoredTeam](https://github.com/TheBoredTeam). Their work is the foundation of everything here.

Notable upstream projects:
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** — Now Playing support for macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** — basis for the Shelf feature

---

## License

GNU General Public License v3.0

Copyright © 2024 TheBoredTeam  
Copyright © 2025 Mark Greene

See [LICENSE](./LICENSE) for the full text.
