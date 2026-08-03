# ThermalForge → boring.notch Integration Plan

Integrates real-time CPU/GPU temperatures and fan RPM data from ThermalForge into boring.notch as a new Thermal tab, a closed-notch sneak-peek alert, and a settings section.

**Scope:** Read-only thermal display. SMC temperature and fan reads are unprivileged on macOS — no daemon, no root, no fan control. This keeps the integration self-contained inside the existing app sandbox.

---

## What Gets Added

| Feature | Where it appears |
|---|---|
| CPU temp, GPU temp, fan RPM | New "Thermal" tab inside the open notch |
| High-temp sneak peek | Closed-notch strip (same mechanism as volume/brightness HUDs) |
| Enable/disable toggle, alert threshold | New "Thermal" settings section |

---

## Files to Copy from ThermalForge (unchanged)

Copy these three files verbatim into a new group `boringNotch/boringNotch/managers/ThermalSMC/`:

| Source (ThermalForge) | Destination (boring.notch) |
|---|---|
| `Sources/ThermalForgeCore/SMCConnection.swift` | `managers/ThermalSMC/SMCConnection.swift` |
| `Sources/ThermalForgeCore/SMCKeys.swift` | `managers/ThermalSMC/SMCKeys.swift` |

> **Why not FanControl.swift?** It's tightly coupled to the daemon's write path and profile system. We only need SMC reads, which `SMCConnection` handles directly.

Add both files to the `boringNotch` Xcode target. No package dependencies are required — they only use IOKit (already linked via AppKit).

Add the IOKit import at the top of `SMCConnection.swift` if not already present:

```swift
import IOKit
```

---

## New Files to Create

### 1. `managers/ThermalManager.swift`

The singleton that owns the SMC connection and publishes thermal state to SwiftUI.

```swift
import Foundation
import Combine

@MainActor
final class ThermalManager: ObservableObject {
    static let shared = ThermalManager()

    @Published var cpuTemp: Float = 0
    @Published var gpuTemp: Float = 0
    @Published var fanRPMs: [Float] = []
    @Published var fanCount: Int = 0
    @Published var isAvailable: Bool = false   // false on VMs / T2-less Macs

    private var smc: SMCConnection?
    private var timer: Timer?

    private init() {
        start()
    }

    func start() {
        guard Defaults[.showThermalTab] else { return }
        do {
            smc = try SMCConnection()
            isAvailable = true
            // Poll every 2 seconds — coarser than ThermalForge's 100ms tick;
            // we only need display cadence, not control cadence.
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            tick()
        } catch {
            isAvailable = false
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        smc = nil
    }

    private func tick() {
        guard let smc else { return }
        Task { @MainActor in
            cpuTemp = peakTemp(smc: smc, prefixes: ["TC", "Tp"])
            gpuTemp = peakTemp(smc: smc, prefixes: ["TG", "Tg"])
            let count = Int(smc.readUInt8("FNum") ?? 0)
            fanCount = count
            fanRPMs = (0..<count).compactMap {
                smc.readFloat(SMCFanKey.key("F%dAc", fan: $0))
            }
            checkSneakPeek()
        }
    }

    private func peakTemp(smc: SMCConnection, prefixes: [String]) -> Float {
        // Enumerate all keys by index and filter by prefix (same approach as ThermalForge)
        // Returns the peak value across all matching keys, filtered 0–150°C
        var peak: Float = 0
        let allKeys = smc.allKeys()
        for key in allKeys {
            guard prefixes.contains(where: { key.hasPrefix($0) }) else { continue }
            if let val = smc.readFloat(key), val > 0, val < 150 {
                peak = max(peak, val)
            }
        }
        return (peak * 10).rounded() / 10   // 0.1°C precision
    }

    private func checkSneakPeek() {
        let threshold = Float(Defaults[.thermalAlertThreshold])
        let maxTemp = max(cpuTemp, gpuTemp)
        guard maxTemp >= threshold else { return }
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .thermalSpike,
            value: Double(maxTemp)
        )
    }
}
```

**Note on `smc.allKeys()`:** This calls `getKeyFromIndex` in a loop — the same approach `FanControl.discover()` uses. Extract that loop from `FanControl.swift` into an `SMCConnection` extension, or add a helper method directly to `SMCConnection.swift`.

---

### 2. `components/Thermal/ThermalView.swift`

The content view rendered in the open notch's Thermal tab.

```swift
import SwiftUI
import Defaults

struct ThermalView: View {
    @ObservedObject private var thermal = ThermalManager.shared

    var body: some View {
        if !thermal.isAvailable {
            Text("SMC unavailable")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            HStack(spacing: 24) {
                thermalGauge(label: "CPU", temp: thermal.cpuTemp)
                thermalGauge(label: "GPU", temp: thermal.gpuTemp)
                if !thermal.fanRPMs.isEmpty {
                    Divider().frame(height: 40).background(.white.opacity(0.2))
                    fanColumn
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func thermalGauge(label: String, temp: Float) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(temp))°")
                .font(.title2.monospacedDigit())
                .foregroundStyle(tempColor(temp))
        }
    }

    private var fanColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(thermal.fanRPMs.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Image(systemName: "fan.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(thermal.fanRPMs[i])) RPM")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func tempColor(_ temp: Float) -> Color {
        switch temp {
        case ..<60:  return .white
        case ..<75:  return .yellow
        case ..<90:  return .orange
        default:     return .red
        }
    }
}
```

---

## Existing Files to Modify

### 3. `enums/generic.swift` — Add `.thermal` to `NotchViews`

```swift
public enum NotchViews {
    case home
    case shelf
    case thermal   // ← add
}
```

---

### 4. `components/Tabs/TabSelectionView.swift` — Add Thermal tab

```swift
let tabs = [
    TabModel(label: "Home",    icon: "house.fill",       view: .home),
    TabModel(label: "Shelf",   icon: "tray.fill",        view: .shelf),
    TabModel(label: "Thermal", icon: "thermometer.medium", view: .thermal),  // ← add
]
```

Gate the tab's visibility on the user setting (if you want it hideable — optional):

```swift
// Inside TabSelectionView.body, filter tabs:
let visibleTabs = tabs.filter { tab in
    tab.view != .thermal || Defaults[.showThermalTab]
}
```

---

### 5. `ContentView.swift` — Handle `.thermal` in `NotchLayout()`

Inside the `switch coordinator.currentView` block:

```swift
case .thermal:
    ThermalView()
```

---

### 6. `models/Constants.swift` — Add Defaults keys

```swift
// Thermal
static let showThermalTab = Key<Bool>("showThermalTab", default: true)
static let thermalAlertThreshold = Key<Int>("thermalAlertThreshold", default: 85)
static let thermalAlertEnabled = Key<Bool>("thermalAlertEnabled", default: true)
```

---

### 7. `BoringViewCoordinator.swift` — Add `SneakContentType.thermalSpike`

```swift
enum SneakContentType {
    case brightness
    case volume
    // ... existing cases ...
    case thermalSpike   // ← add
}
```

---

### 8. `components/Live activities/SystemEventIndicatorModifier.swift`

Add a case for thermal sneak peek rendering:

```swift
case .thermalSpike:
    Image(systemName: "thermometer.high")
        .foregroundStyle(.orange)
    Text("\(Int(coordinator.sneakPeek.value ?? 0))°")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.orange)
```

This follows the same pattern as the volume/brightness HUD cases already in this file.

---

### 9. `components/Settings/SettingsView.swift` — Add Thermal section

**Add a NavigationLink** in the sidebar list:

```swift
NavigationLink("Thermal", value: "Thermal")
```

**Add a case** in the `switch selectedTab` block:

```swift
case "Thermal":
    ThermalSettings()
```

**Add the section struct** at the bottom of the file:

```swift
struct ThermalSettings: View {
    @Default(.showThermalTab) var showThermalTab
    @Default(.thermalAlertEnabled) var thermalAlertEnabled
    @Default(.thermalAlertThreshold) var thermalAlertThreshold

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show Thermal tab", isOn: $showThermalTab)
            }
            Section("Alerts") {
                Toggle("Alert on high temperature", isOn: $thermalAlertEnabled)
                if thermalAlertEnabled {
                    Stepper("\(thermalAlertThreshold)°C threshold",
                            value: $thermalAlertThreshold,
                            in: 70...100, step: 5)
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

---

### 10. `boringNotchApp.swift` — React to settings changes

In `AppDelegate.applicationDidFinishLaunching` (or wherever other managers are wired up), observe the `showThermalTab` setting to start/stop the manager when the user toggles it:

```swift
Defaults.publisher(.showThermalTab)
    .sink { change in
        if change.newValue {
            ThermalManager.shared.start()
        } else {
            ThermalManager.shared.stop()
        }
    }
    .store(in: &cancellables)
```

Also gate the sneak-peek emission on `thermalAlertEnabled` inside `ThermalManager.checkSneakPeek()`:

```swift
guard Defaults[.thermalAlertEnabled] else { return }
```

---

## Data Flow After Integration

```
[IOKit / AppleSMC kernel driver]
        ↓ (IOConnectCallStructMethod, every 2s)
ThermalManager.tick()
        ↓ peakTemp(prefixes: ["TC","Tp"]) → cpuTemp
        ↓ peakTemp(prefixes: ["TG","Tg"]) → gpuTemp
        ↓ readFloat("F0Ac") ... → fanRPMs[]
        ↓ @Published properties
ThermalView (SwiftUI, Thermal tab)
        ↓ if maxTemp ≥ threshold
BoringViewCoordinator.toggleSneakPeek(.thermalSpike, value: temp)
        ↓ @Published sneakPeek
ContentView NotchLayout() → SystemEventIndicatorModifier → orange thermometer HUD
```

---

## Implementation Order

1. Copy `SMCConnection.swift` and `SMCKeys.swift` into the Xcode project and add to the target.
2. Extend `SMCConnection` with an `allKeys()` method (enumerate by index) if not already there.
3. Create `ThermalManager.swift`. Build and confirm the SMC opens cleanly.
4. Add `NotchViews.thermal`, the tab entry, and the `ContentView` case.
5. Create `ThermalView.swift`. Verify live temperature data appears in the open notch.
6. Add `SneakContentType.thermalSpike` and wire `SystemEventIndicatorModifier`.
7. Add the three `Defaults.Keys` and the `ThermalSettings` section in `SettingsView`.
8. Wire `showThermalTab` observer in `AppDelegate`.

---

## Things to Watch Out For

| Risk | Mitigation |
|---|---|
| SMC unavailable on VMs or some non-Apple-Silicon machines | `isAvailable = false` guard in `ThermalManager.start()`; `ThermalView` shows a graceful fallback message |
| `allKeys()` is slow (full SMC key enumeration) | Call it once at startup, cache the key list; only re-enumerate if the key count (`FNum`) changes |
| IOKit linking | `SMCConnection` uses IOKit — confirm `IOKit.framework` is linked in the Xcode target's "Frameworks, Libraries" build phase |
| `getKeyFromIndex` needs root on some macOS versions | Read-only SMC access (temp + fan actual RPM) is unprivileged; only writes need root. Confirm on target OS version before shipping |
| Sneak-peek spam at sustained high temps | Add a minimum re-trigger cooldown (e.g., 60s) inside `checkSneakPeek()` using a `lastAlertDate` timestamp |
| Timer on background thread calling `@MainActor` methods | The `Task { @MainActor in ... }` block inside `tick()` ensures UI updates hop to the main actor correctly |
