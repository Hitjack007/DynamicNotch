# How boring.notch Replaces System HUDs

## Overview

When you press volume or brightness keys, macOS normally shows a translucent overlay HUD via BezelServices. boring.notch replaces this entirely by (1) intercepting the key event before the system sees it, (2) applying the change itself, and (3) displaying its own in-notch HUD.

---

## Full Pipeline

```
Media Key Press
  ↓
CGEvent Tap (HID level, head insert)
  ↓
handleEvent() extracts key type & state
  ↓
handleKeyPress() routes to appropriate manager
  ↓
VolumeManager / BrightnessManager update system value
  ↓
Manager calls BoringViewCoordinator.toggleSneakPeek()
  ↓
sneakPeek @Published property updates → SwiftUI re-renders
  ↓
ContentView shows InlineHUD / OpenNotchHUD / SystemEventIndicator
  ↓
EVENT CONSUMED (return nil) → system never sees it → no BezelServices HUD
```

---

## Step 1 — Key Interception (`MediaKeyInterceptor.swift`)

- Creates a **CGEvent tap** at `.cghidEventTap` with `.headInsertEventTap` placement — this puts it at the very beginning of the event chain, before the OS.
- Filters for `CGEventType(rawValue: 14)` — system-defined events (media/special keys).
- Extracts key code and key state from `NSEvent.data1`:
  - Key code: `(data1 & 0xFFFF_0000) >> 16`
  - Key state: `((data1 & 0xFF00) >> 8)` — only processes `0xA` (key-down)
- Key codes handled (via `NXKeyType` enum):

| Code | Action |
|------|--------|
| 0 | Volume up |
| 1 | Volume down |
| 7 | Mute toggle |
| 2 | Brightness up |
| 3 | Brightness down |
| 21 | Keyboard brightness up |
| 22 | Keyboard brightness down |

- Requires **Accessibility permission** — checks via XPC helper before enabling the tap.

---

## Step 2 — System HUD Suppression

**There are no explicit HUD suppression API calls.** The suppression is achieved by returning `nil` from the CGEvent callback instead of `Unmanaged.passRetained(cgEvent)`. This consumes the event — the system never receives it and therefore never triggers BezelServices to show a HUD. Simple and non-invasive.

This only activates when `hudReplacement` is enabled in user defaults (`BoringViewCoordinator.toggleSneakPeek` early-returns if the setting is off).

---

## Step 3 — Applying the System Change

### Volume (`VolumeManager.swift`)
- Uses **CoreAudio** directly: `AudioObjectPropertyAddress` + `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData`
- Reads/writes `kAudioDevicePropertyVolumeScalar` on the default output device
- Mute: tries hardware mute first (`kAudioDevicePropertyMute`), falls back to software mute (set volume to 0)
- Feedback click: plays `/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff`

### Screen Brightness (`BrightnessManager.swift` + XPC helper)
- Delegated to the **XPC helper** (`BoringNotchXPCHelper`) because the app sandbox can't access private frameworks directly
- Helper dynamically loads `DisplayServices.framework` via `dlopen` and calls:
  - `DisplayServicesGetBrightness()` — read
  - `DisplayServicesSetBrightness()` — write
- Fallback: IOKit `IODisplaySetFloatParameter()` with `kIODisplayBrightnessKey`

### Keyboard Brightness (XPC helper)
- Helper loads `CoreBrightness.framework` via `dlopen`
- Calls `KeyboardBrightnessClient` class methods via `NSSelectorFromString`:
  - `brightnessForKeyboard:` (getter)
  - `setBrightness:forKeyboard:` (setter)
- Keyboard ID hardcoded as `1` (UInt64)

---

## Step 4 — Showing the Custom HUD

### State Management (`BoringViewCoordinator.swift`)
- Managers call `BoringViewCoordinator.shared.toggleSneakPeek(status: true, type:, value:)`
- Updates `@Published var sneakPeek` with:
  - `show: Bool`
  - `type: SneakContentType` (`.volume`, `.brightness`, `.backlight`, `.mic`)
  - `value: CGFloat` (0.0–1.0)
  - `icon: String?` (optional override)
- A `Task` auto-hides after `sneakPeekDuration` (default **1.5 seconds**)

### HUD Components (only shown when notch is **closed**)

**`InlineHUD`** — compact inline format inside the closed notch
- Icon + label + draggable progress bar
- Optional percentage label (`showClosedNotchHUDPercentage` setting)
- Drag updates the system value in real time

**`SystemEventIndicatorModifier`** — alternative closed-notch style
- Icon (20 px) + progress bar with optional gradient/accent
- Different spacing/layout than InlineHUD

**`OpenNotchHUD`** — shown when notch is open
- Capsule overlay: icon + slider + percentage
- Gradient and accent color configurable via settings

---

## Step 5 — Window Positioning

**`BoringNotchWindow`** (NSPanel subclass):
- `level = .mainMenu + 3` — above the menu bar, below native system UI
- `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`
- Transparent, non-movable, floating

**`BoringNotchSkyLightWindow`** — extends this for lock-screen support:
- Uses private `SkyLight.framework` (loaded via `dlopen`/`dlsym`)
- Calls `SLSRemoveWindowsFromSpaces()` for space management on the lock screen
- Supports hiding from screen recording: `sharingType = .none`

---

## XPC Helper Protocol (`BoringNotchXPCHelperProtocol.swift`)

The helper runs as a privileged process to access private APIs the sandbox blocks:

```
isAccessibilityAuthorized(reply:)
requestAccessibilityAuthorization()
ensureAccessibilityAuthorization(_:reply:)
isKeyboardBrightnessAvailable(reply:)
currentKeyboardBrightness(reply:)
setKeyboardBrightness(_:reply:)
isScreenBrightnessAvailable(reply:)
currentScreenBrightness(reply:)
setScreenBrightness(_:reply:)
```

Service name: `theboringteam.boringnotch.BoringNotchXPCHelper`

---

## Private APIs Used

| Framework | API | Purpose |
|-----------|-----|---------|
| ApplicationServices | `AXIsProcessTrusted()` | Accessibility auth check |
| ApplicationServices | `AXIsProcessTrustedWithOptions()` | Accessibility prompt |
| CoreAudio | `AudioObject*` functions | Volume / mute control |
| DisplayServices (private) | `DisplayServicesGetBrightness()` | Read screen brightness |
| DisplayServices (private) | `DisplayServicesSetBrightness()` | Write screen brightness |
| CoreBrightness (private) | `KeyboardBrightnessClient` class | Keyboard backlight control |
| IOKit | `IODisplaySetFloatParameter()` | Fallback brightness via IO |
| SkyLight (private) | `SLSRemoveWindowsFromSpaces()` | Lock-screen window management |

---

## Key Files

| File | Role |
|------|------|
| `observers/MediaKeyInterceptor.swift` | CGEvent tap, key parsing, event consumption |
| `managers/VolumeManager.swift` | CoreAudio volume/mute control |
| `managers/BrightnessManager.swift` | Brightness control (delegates to XPC) |
| `XPCHelperClient/XPCHelperClient.swift` | XPC connection to privileged helper |
| `XPCHelperClient/BoringNotchXPCHelperProtocol.swift` | XPC interface definition |
| `models/BoringViewCoordinator.swift` | `sneakPeek` state, `toggleSneakPeek()` |
| `components/Live activities/InlineHUD.swift` | Closed-notch HUD view |
| `components/Live activities/OpenNotchHUD.swift` | Open-notch HUD view |
| `components/Live activities/SystemEventIndicatorModifier.swift` | Alternative HUD style |
