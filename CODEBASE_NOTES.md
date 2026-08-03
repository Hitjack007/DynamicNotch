# boring.notch — Codebase Notes

A comprehensive reference for understanding, navigating, and extending the project.

---

## What It Does

boring.notch is a macOS menu-bar utility that transforms the notch (or the menu bar area on non-notch Macs) into an interactive panel. When hovered or swiped it expands to show music controls, a file shelf, calendar, webcam mirror, battery info, and system HUDs (volume/brightness). It also replaces macOS's native volume/brightness HUD overlays.

---

## High-Level Architecture

```
DynamicNotchApp (App)
└── AppDelegate (NSApplicationDelegate)
    ├── BoringNotchSkyLightWindow (NSPanel) — one per screen
    │   └── ContentView (SwiftUI root)
    │       ├── NotchShape — the pill/bezel shape
    │       ├── [closed] MusicLiveActivity / InlineHUD / BatteryNotif / FaceAnimation
    │       ├── [open] BoringHeader (tabs + battery icon + camera toggle + gear)
    │       └── [open] NotchHomeView  ← or ←  ShelfView
    └── BoringViewCoordinator.shared (singleton — global state)
        └── MusicManager.shared (singleton — music state + active controller)
```

---

## File Map

### Entry Point & Window

| File | Role |
|------|------|
| `boringNotch/boringNotch/boringNotchApp.swift` | `@main` struct + `AppDelegate`. Creates windows, handles screen changes, keyboard shortcuts, onboarding, lock-screen events. |
| `boringNotch/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift` | Custom `NSPanel` subclass. Sits at `level = .mainMenu + 3`, forces `.darkAqua`. Uses private SkyLight framework to optionally appear on the lock screen. |
| `boringNotch/boringNotch/components/Notch/BoringNotchWindow.swift` | Older `NSPanel` base class (no SkyLight). Not used for the main window anymore but kept. |
| `boringNotch/boringNotch/sizing/matters.swift` | All sizing constants. **The single source of truth for dimensions.** |

### State & Coordination

| File | Role |
|------|------|
| `boringNotch/boringNotch/models/BoringViewModel.swift` | Per-screen ViewModel. Owns `notchState` (`.open`/`.closed`), notch size, drag/drop targeting flags, camera expanded flag. One instance per physical screen. |
| `boringNotch/boringNotch/BoringViewCoordinator.swift` | `@MainActor` singleton. Owns `currentView` (`.home`/`.shelf`), `sneakPeek`, `expandingView`, screen UUID, first-launch state. |
| `boringNotch/boringNotch/models/Constants.swift` | **All `Defaults.Keys`.** Every user-facing setting lives here. Also defines many supporting enums. |
| `boringNotch/boringNotch/enums/generic.swift` | Core domain enums: `NotchState`, `NotchViews`, `ContentType`, `SettingsEnum`, `DownloadIndicatorStyle`, `SliderColorEnum`, etc. |

### UI — Notch Views

| File | Role |
|------|------|
| `boringNotch/boringNotch/ContentView.swift` | Root SwiftUI view. Handles shape, animations, hover, gestures (swipe to open/close), drop zones, `NotchLayout()` builder function. |
| `boringNotch/boringNotch/components/Notch/NotchShape.swift` | Custom `Shape` that draws the notch pill with animatable top/bottom corner radii. |
| `boringNotch/boringNotch/components/Notch/BoringHeader.swift` | The header row rendered inside the open notch: tab selector (left), notch chip overlay (centre), battery/camera/settings icons (right). |
| `boringNotch/boringNotch/components/Notch/NotchHomeView.swift` | The "Home" tab content: `MusicPlayerView` → `AlbumArtView` + `MusicControlsView` (slot toolbar, slider, lyrics, song info). Also hosts `CalendarView` and `CameraPreviewView`. |
| `boringNotch/boringNotch/components/Shelf/Views/ShelfView.swift` | The "Shelf" tab. Drag-and-drop file/URL tray with Quick Look. |

### UI — Tabs

| File | Role |
|------|------|
| `boringNotch/boringNotch/components/Tabs/TabSelectionView.swift` | Tab bar in the header. The `tabs` array at the top lists all tab models. Add a new tab here and in `NotchViews`. |
| `boringNotch/boringNotch/components/Tabs/TabButton.swift` | Individual tab button. |

### UI — Live Activities (Closed State)

| File | Role |
|------|------|
| `boringNotch/boringNotch/components/Live activities/LiveActivityModifier.swift` | Helper modifier for the mini live-activity strip. |
| `boringNotch/boringNotch/components/Live activities/SystemEventIndicatorModifier.swift` | Pops out next to notch for volume/brightness HUD. |
| `boringNotch/boringNotch/components/Live activities/InlineHUD.swift` | Inline mode HUD (inside the notch pill). |
| `boringNotch/boringNotch/components/Live activities/BoringBattery.swift` | Battery icon view. |
| `boringNotch/boringNotch/components/Live activities/MarqueeTextView.swift` | `MarqueeText` — scrolling text for tight spaces. Use this for any text that might overflow. |
| `boringNotch/boringNotch/components/Live activities/OpenNotchHUD.swift` | HUD shown inside the open notch header area. |
| `boringNotch/boringNotch/components/Live activities/DownloadView.swift` | Download progress indicator. |

### Media Controllers

| File | Role |
|------|------|
| `boringNotch/boringNotch/MediaControllers/MediaControllerProtocol.swift` | Protocol every media controller must conform to. |
| `boringNotch/boringNotch/MediaControllers/NowPlayingController.swift` | macOS Now Playing API. May be deprecated on newer macOS. |
| `boringNotch/boringNotch/MediaControllers/AppleMusicController.swift` | AppleScript bridge to Music.app. |
| `boringNotch/boringNotch/MediaControllers/SpotifyController.swift` | AppleScript bridge to Spotify.app. |
| `boringNotch/boringNotch/MediaControllers/YouTube Music Controller/` | Local YouTube Music app API. |
| `boringNotch/boringNotch/managers/MusicManager.swift` | Singleton that owns the active controller, publishes all playback state (`songTitle`, `albumArt`, `isPlaying`, etc.), handles artwork, lyrics, sneak peek. |
| `boringNotch/boringNotch/models/PlaybackState.swift` | Plain struct carrying a snapshot of playback state from any controller. |
| `boringNotch/boringNotch/models/MusicControlButton.swift` | Enum of all control button types (shuffle, previous, play/pause, etc.) with label/icon metadata. The user can configure which slots show which buttons. |

### Managers

| File | Role |
|------|------|
| `boringNotch/boringNotch/managers/BatteryActivityManager.swift` | Battery level + charging state. |
| `boringNotch/boringNotch/managers/BrightnessManager.swift` | Read/set screen brightness. |
| `boringNotch/boringNotch/managers/VolumeManager.swift` | Read/set system volume. |
| `boringNotch/boringNotch/managers/CalendarManager.swift` | Fetches EventKit events/reminders. |
| `boringNotch/boringNotch/managers/WebcamManager.swift` | Camera session management. |
| `boringNotch/boringNotch/managers/NotchSpaceManager.swift` | Controls which Mission Control space the window appears in. |
| `boringNotch/boringNotch/managers/ImageService.swift` | Async image helpers. |

### Reusable UI Components

| File | Role |
|------|------|
| `boringNotch/boringNotch/components/HoverButton.swift` | **The standard media-control button.** Capsule bg appears on hover. Use this for any icon button in the notch. |
| `boringNotch/boringNotch/extensions/ActionBar.swift` | View modifier that adds a bottom action bar (divider + buttons). |
| `boringNotch/boringNotch/extensions/ConditionalModifier.swift` | `.conditionalModifier(bool) { view in ... }` helper. |
| `boringNotch/boringNotch/extensions/Button+Bouncing.swift` | Bouncing press animation for buttons. |
| `boringNotch/boringNotch/extensions/Color+AccentColor.swift` | `.effectiveAccent` — respects custom accent color setting. |
| `boringNotch/boringNotch/extensions/MouseTracker.swift` | Global mouse tracking without accessibility permissions. |
| `boringNotch/boringNotch/components/LottieView.swift` | Lottie animation wrapper. |
| `boringNotch/boringNotch/components/Music/MusicVisualizer.swift` | Audio spectrum bars. |

### Settings

| File | Role |
|------|------|
| `boringNotch/boringNotch/components/Settings/SettingsView.swift` | All settings UI. One large file with a `NavigationSplitView` and individual structs per section (GeneralSettings, Appearance, Media, CalendarSettings, HUD, Charge, Shelf, Shortcuts, Advanced, About). **Add new settings sections here.** |
| `boringNotch/boringNotch/components/Settings/SettingsWindowController.swift` | Singleton that manages the settings NSWindow lifecycle. Call `SettingsWindowController.shared.showWindow()` to open settings. |
| `boringNotch/boringNotch/components/Settings/MusicSlotConfigurationView.swift` | Drag-and-drop music control slot editor. |

---

## Sizing Constants (matters.swift)

```swift
openNotchSize    = CGSize(width: 640, height: 190)   // expanded notch
windowSize       = CGSize(width: 660, height: 210)   // NSPanel size (adds shadow padding)
cornerRadiusInsets = (
    opened: (top: 19, bottom: 24),
    closed:  (top: 6,  bottom: 14)
)
MusicPlayerImageSizes.cornerRadiusInset = (opened: 13, closed: 4)
```

The closed notch size is dynamic (computed from screen safe area insets or user settings). Use `getClosedNotchSize(screenUUID:)` to get it.

---

## The Settings System (`Defaults`)

All settings are `Defaults.Keys` defined in `Constants.swift` and stored in UserDefaults via the [Defaults](https://github.com/sindresorhus/Defaults) package.

Read anywhere with:
```swift
Defaults[.someKey]           // read
Defaults[.someKey] = value   // write
@Default(.someKey) var foo   // SwiftUI binding
```

Observe changes reactively:
```swift
Defaults.publisher(.someKey)
    .sink { change in ... }
```

---

## Data Flow

```
[Physical media app] → MediaControllerProtocol
                           ↓ playbackStatePublisher (AnyPublisher<PlaybackState, Never>)
                       MusicManager.shared
                           ↓ @Published properties
                       SwiftUI views (MusicControlsView, AlbumArtView, etc.)
```

```
[User hover/gesture] → ContentView.handleHover / handleDownGesture
                           ↓
                       BoringViewModel.open() / close()
                           ↓ @Published notchState
                       ContentView (re-renders with new shape/content)
```

```
[System event: volume changed] → VolumeManager
                                      ↓
                                  BoringViewCoordinator.toggleSneakPeek(status: true, type: .volume, value: ...)
                                      ↓ @Published sneakPeek
                                  ContentView NotchLayout() → shows SystemEventIndicatorModifier
```

---

## How to Add Features

### Add a new tab inside the opened notch

1. **`enums/generic.swift`** — Add a case to `NotchViews`:
   ```swift
   public enum NotchViews {
       case home
       case shelf
       case myNewTab   // ← add this
   }
   ```

2. **`components/Tabs/TabSelectionView.swift`** — Add a `TabModel` to the `tabs` array:
   ```swift
   let tabs = [
       TabModel(label: "Home", icon: "house.fill", view: .home),
       TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
       TabModel(label: "My Tab", icon: "star.fill", view: .myNewTab),  // ← add this
   ]
   ```

3. **`ContentView.swift`** — Handle the case in `NotchLayout()` inside the `switch coordinator.currentView` block:
   ```swift
   case .myNewTab:
       MyNewTabView()
   ```

4. Create `MyNewTabView` in `components/` following the same structure as `NotchHomeView`.

---

### Add a new user setting

1. **`models/Constants.swift`** — Add a `Defaults.Key`:
   ```swift
   static let myNewSetting = Key<Bool>("myNewSetting", default: false)
   ```

2. **`components/Settings/SettingsView.swift`** — Add the UI control inside the appropriate section struct (e.g. `Appearance`, `General`, etc.):
   ```swift
   Toggle("My New Setting", isOn: Defaults.$myNewSetting)
   ```

3. Use the setting in any view or manager:
   ```swift
   @Default(.myNewSetting) var myNewSetting
   // or
   if Defaults[.myNewSetting] { ... }
   ```

4. If you need a new settings *section* (tab in the sidebar):
   - Add a `NavigationLink` in `SettingsView.body`'s list
   - Add a `case "MySectionName":` in the `switch selectedTab` block
   - Create a new `struct MySectionName: View`

---

### Add a new media controller

1. **`models/Constants.swift`** — Add to `MediaControllerType`:
   ```swift
   enum MediaControllerType: String, CaseIterable, ... {
       case nowPlaying = "Now Playing"
       case appleMusic = "Apple Music"
       case spotify    = "Spotify"
       case youtubeMusic = "YouTube Music"
       case myApp      = "My App"     // ← add this
   }
   ```

2. **`MediaControllers/`** — Create `MyAppController.swift` conforming to `MediaControllerProtocol`:
   ```swift
   class MyAppController: ObservableObject, MediaControllerProtocol {
       var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { ... }
       var supportsVolumeControl: Bool { false }
       var supportsFavorite: Bool { false }
       // implement: play, pause, seek, nextTrack, previousTrack, togglePlay,
       //            toggleShuffle, toggleRepeat, setVolume, isActive, updatePlaybackInfo, setFavorite
   }
   ```

3. **`managers/MusicManager.swift`** — Add the case to `createController(for:)`:
   ```swift
   case .myApp:
       newController = MyAppController()
   ```

4. **`components/Onboarding/MusicControllerSelectionView.swift`** — Add it to the picker.

---

### Add a new music control button slot

1. **`models/MusicControlButton.swift`** — Add a case with `label` and `iconName`:
   ```swift
   enum MusicControlButton: String, ... {
       // ...
       case myButton
   
       var label: String {
           switch self {
           case .myButton: return "My Button"
           // ...
           }
       }
       var iconName: String {
           switch self {
           case .myButton: return "star.fill"
           // ...
           }
       }
   }
   ```
   Also add it to `pickerOptions` so it shows in the settings editor.

2. **`components/Notch/NotchHomeView.swift`** — Add a case to `slotView(for:)`:
   ```swift
   case .myButton:
       HoverButton(icon: "star.fill", scale: .medium) {
           // action
       }
   ```

---

### Add a new closed-notch live activity

The closed-notch content is selected by a chain of `if/else if` conditions in `ContentView.NotchLayout()` (around lines 260–302). To add a new state:

1. Add any new state to `BoringViewCoordinator` (a `@Published` bool, or a new `SneakContentType` case).
2. Add an `else if` branch in the closed-notch section of `NotchLayout()`.
3. The view you return here should match `vm.effectiveClosedNotchHeight` in height and fit within `vm.closedNotchSize.width`.

---

### Add a new sneak-peek type (closed-notch system event)

1. **`BoringViewCoordinator.swift`** — Add a case to `SneakContentType`:
   ```swift
   enum SneakContentType {
       case brightness
       case volume
       // ...
       case myEvent
   }
   ```

2. Call `BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .myEvent, value: someFloat)` from your manager.

3. **`components/Live activities/SystemEventIndicatorModifier.swift`** — Handle the new type in the icon/label rendering.

4. **`BoringHeader.swift`** — Update `isHUDType(_:)` if it should show in the open-notch HUD style.

---

## Design Language — Rules to Follow

### Colors
- Background is always **pure black** (`Color.black` / `.black`). Never use system background colors.
- Text: white for primary, gray for secondary, album-art-derived color for accents (via `MusicManager.shared.avgColor`).
- Accent: use `.effectiveAccent` (from `Color+AccentColor.swift`) — it respects the user's custom accent color setting.
- The window appearance is forced to `.darkAqua`. Never add `.light` appearance elements.

### Shapes & Corner Radii
- Use `NotchShape(topCornerRadius:bottomCornerRadius:)` for the outer bezel.
- Use `RoundedRectangle(cornerRadius: ...)` for card-like containers.
- Use `Capsule()` for pill-shaped buttons and tab indicators.
- Use the constants from `matters.swift` and `MusicPlayerImageSizes` for image corner radii.

### Buttons
- Use `HoverButton(icon:iconColor:scale:action:)` for all icon buttons in the notch.
  - `.large` scale → 40×40 hit area (for play/pause)
  - `.medium` scale → 30×30 hit area (for everything else)
- Use `PlainButtonStyle()` everywhere — the default button ring looks wrong on black.

### Typography
- Song title: `.headline`
- Artist / secondary info: `.headline` at `.medium` weight (or just `.body`)
- Captions / timestamps: `.caption`
- Use `MarqueeText` (not `Text`) for anything that might overflow its container.

### Animations
- Open/close: `Animation.spring(response: 0.42, dampingFraction: 0.8)` (open) / `(0.45, 1.0)` (close)
- Interactive gestures: `Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8)`
- Smooth state changes: `Animation.smooth` or `withAnimation(.smooth)`
- Content transitions (text, icons): `.symbolEffect` (already default on `HoverButton`)
- Always wrap state mutations that should animate in `withAnimation { ... }`.

### Padding & Spacing
- Standard inner padding between elements: `16` pt (the `spacing` constant from `Constants.swift`)
- Open notch horizontal padding: driven by `cornerRadiusInsets.opened.top` (~19 pt) plus 12 pt bottom padding
- Header height: `max(24, vm.effectiveClosedNotchHeight)` — always at least 24 pt

### Drop Zones
- Files can be dropped anywhere on the closed notch → opens shelf automatically.
- The `GeneralDropTargetDelegate` on `NotchLayout()` and the `isTargeted` binding on shelf are the two handlers.
- When adding a new drop target, set `vm.dropEvent = true` before returning `true` to prevent auto-close.

---

## Files to Treat With Care

| File | Why |
|------|-----|
| `sizing/matters.swift` | `openNotchSize` and `windowSize` are load-bearing for the whole layout. Every view assumes 640×190 content. |
| `boringNotchApp.swift` | AppDelegate is complex — handles multi-display, screen lock, screen config changes. Test any change across single and multiple displays. |
| `components/Notch/BoringNotchSkyLightWindow.swift` | `level = .mainMenu + 3` keeps the notch above full-screen apps. If this changes the notch disappears under Spotlight etc. |
| `models/Constants.swift` — the `Defaults.Keys` names | Renaming a key silently resets that preference for all users. Never rename; add new keys instead. |
| `BoringViewCoordinator.swift` — `@AppStorage` keys | Same issue — `"firstLaunch"`, `"showWhatsNew"`, `"openLastTabByDefault"` etc. are serialised; renaming them breaks data continuity. |
| `MediaControllers/MediaControllerProtocol.swift` | Adding required protocol methods is a breaking change to all four existing controllers. Add `extension` defaults instead. |

---

## Files Safe to Freely Edit

- Anything inside `components/Settings/SettingsView.swift` (adding new UI rows doesn't affect runtime behaviour)
- Any individual view/component file — they're leaf nodes; changes are isolated
- `components/Notch/NotchHomeView.swift` — add/remove subviews freely
- `enums/generic.swift` — adding new enum cases is always safe
- `models/MusicControlButton.swift` — adding new button types is additive

---

## Package Dependencies

| Package | Purpose |
|---------|---------|
| `Defaults` | Typed UserDefaults wrapper. Central to ALL settings. |
| `SkyLightWindow` | Private SkyLight API for appearing on the lock screen. |
| `KeyboardShortcuts` | Global hotkey registration (toggle notch, sneak peek). |
| `Sparkle` | In-app auto-update. |
| `LaunchAtLogin` | macOS launch-at-login setting. |
| `Lottie` | JSON-based vector animations (welcome screen, visualiser). |
| `Pow` | Extra SwiftUI transition effects. |
| `SwiftUIIntrospect` | Reaches into AppKit from SwiftUI (used in Settings). |
| `MacroVisionKit` | Likely used for macro/lens effects in camera view. |
| `AsyncXPCConnection` | XPC bridge to a privileged helper for accessibility/HUD replacement. |
| `swift-collections` | `OrderedDictionary` and similar structures. |
| `swift-syntax` | Macro support (compile-time, not runtime). |

---

## XPC Helper

There is a small XPC helper process (`XPCHelperClient/`) used for accessibility authorization checks and media key interception. It is accessed through `XPCHelperClient.shared`. The protocol is defined in `BoringNotchXPCHelperProtocol.swift`. Don't modify the XPC protocol without updating both sides (the client and the helper target).

---

## Common Patterns

**Reading a Defaults value in a View:**
```swift
@Default(.showBatteryIndicator) var showBatteryIndicator
// or inline:
if Defaults[.showBatteryIndicator] { ... }
```

**Observing a Defaults value in a class:**
```swift
Defaults.publisher(.myKey)
    .sink { change in self.doSomething(change.newValue) }
    .store(in: &cancellables)
```

**Posting a sneak peek from a manager:**
```swift
BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: 0.75)
```

**Opening the notch programmatically:**
```swift
// From AppDelegate (has reference to vm):
vm.open()
// or via keyboard shortcut callback already wired in boringNotchApp.swift
```

**Adding a button to the notch header (right side):**
Edit `BoringHeader.swift` inside the `HStack(spacing: 4)` block (the trailing side). Follow the existing pattern — `Capsule().fill(.black).frame(30, 30).overlay { Image(systemName: ...) }` wrapped in a `Button`.

**Conditionally showing content at a specific size:**
```swift
.frame(width: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
```
Always use `vm.effectiveClosedNotchHeight` (not `vm.closedNotchSize.height`) for the closed height, because it returns 0 when the notch should be hidden.
