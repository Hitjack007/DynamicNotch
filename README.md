# DynamicNotch

A heavily extended fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam — making the MacBook notch genuinely useful with live system stats, responsive audio visualization, and smarter HUD replacements.

---

## What's new in this fork

- **Dynamic notch sizing** — the notch expands and contracts based on what's happening on screen
- **Responsive spectrogram** — real-time audio visualizer driven by screen recording capture
- **Fan & thermal monitoring** — live fan speed and CPU temperature in the notch
- **System stats** — CPU usage at a glance
- **Caffeine integration** — prevent sleep directly from the notch
- **Custom system HUDs** — replaces macOS volume, brightness, and keyboard backlight overlays with notch-native versions

---

## Features (inherited from boring.notch)

- Music playback live activity with album art and controls
- Calendar and Reminders integration
- File shelf with AirDrop support
- Mirror / webcam view
- Battery charging indicator
- Gesture controls
- Notch size customization for different display sizes

---

## System Requirements

- macOS **14 Sonoma** or later
- Apple Silicon or Intel Mac

---

## Building from Source

### Prerequisites

- macOS 15 or later
- Xcode 26 or later

### Steps

1. Clone the repo:
   ```bash
   git clone https://github.com/Hitjack007/DynamicNotch.git
   cd DynamicNotch
   ```

2. Open the project:
   ```bash
   open boringNotch.xcodeproj
   ```

3. In Xcode, set your own development team under **Signing & Capabilities** for both the main target and the `BoringNotchXPCHelper` target.

4. Press **Cmd + R** to build and run.

---

## Creating a Release Build

To produce a distributable `.app` you can share via GitHub Releases:

### 1. Archive the app in Xcode

- Select **Product > Archive** from the menu bar (make sure the scheme is set to `boringNotch` and destination is **Any Mac**).
- Once the archive appears in the Organizer window, click **Distribute App**.
- Choose **Direct Distribution**, then **Export**.
- Save the exported `.app` somewhere (e.g. your Desktop).

### 2. Package it as a DMG

Open Terminal and run:

```bash
# Create a temporary folder with the app
mkdir -p /tmp/DynamicNotch-dmg
cp -R /path/to/boringNotch.app /tmp/DynamicNotch-dmg/

# Create the DMG
hdiutil create \
  -volname "DynamicNotch" \
  -srcfolder /tmp/DynamicNotch-dmg \
  -ov \
  -format UDZO \
  ~/Desktop/DynamicNotch.dmg
```

### 3. Publish a GitHub Release

Using the GitHub CLI (install via `brew install gh` if needed):

```bash
gh release create v1.0.0 ~/Desktop/DynamicNotch.dmg \
  --title "DynamicNotch v1.0.0" \
  --notes "Initial release."
```

This creates a release tagged `v1.0.0` and attaches the DMG as a downloadable asset. Users can then download and drag the app to `/Applications`.

> **Note:** Without an Apple Developer account, macOS will show an unidentified developer warning. Users can bypass it by running:
> ```bash
> xattr -dr com.apple.quarantine /Applications/boringNotch.app
> ```

---

## Credits

DynamicNotch is built on top of [boring.notch](https://github.com/TheBoredTeam/boring.notch), originally created by [TheBoredTeam](https://github.com/TheBoredTeam). Their work made this possible — the core notch window, music controls, shelf, calendar integration, and HUD system all originate from their project.

Notable upstream dependencies:
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** — Now Playing support for macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** — basis for the Shelf feature

---

## License

DynamicNotch is a derivative work of boring.notch and is distributed under the **GNU General Public License v3.0**.

Copyright © 2024 TheBoredTeam  
Copyright © 2025 Mark Greene

See [LICENSE](./LICENSE) for the full text.
