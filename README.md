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

- macOS **14 Sonoma** or later
- MacBook with a notch (any Apple Silicon model, or Intel with notch display)

---

## Installation

1. Download the latest **DynamicNotch.dmg** from the [Releases](https://github.com/Hitjack007/DynamicNotch/releases/latest) page
2. Open the DMG and drag **DynamicNotch** to your Applications folder
3. Before opening, run this once in Terminal to clear the macOS security warning:
   ```bash
   xattr -dr com.apple.quarantine /Applications/boringNotch.app
   ```
4. Open the app — your notch is now alive

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
open boringNotch.xcodeproj
```

In Xcode, set your own development team under **Signing & Capabilities** for both `boringNotch` and `BoringNotchXPCHelper`, then press **Cmd + R**.

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
