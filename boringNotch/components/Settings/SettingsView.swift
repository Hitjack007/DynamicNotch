//
//  SettingsView.swift
//  boringNotch
//
//  Created by Mark Greene on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Notch") {
                    NavigationLink(value: "General") {
                        Label("General", systemImage: "gear")
                    }
                    NavigationLink(value: "Appearance") {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                }

                Section("Features") {
                    NavigationLink(value: "Displays") {
                        Label("Displays", systemImage: "display.2")
                    }
                    NavigationLink(value: "Media") {
                        Label("Media", systemImage: "play.laptopcomputer")
                    }
                    NavigationLink(value: "Calendar") {
                        Label("Calendar", systemImage: "calendar")
                    }
                    NavigationLink(value: "HUD") {
                        Label("HUDs", systemImage: "dial.medium.fill")
                    }
                    NavigationLink(value: "Battery") {
                        Label("Battery", systemImage: "battery.100.bolt")
                    }
                    NavigationLink(value: "Downloads") {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    NavigationLink(value: "Thermal") {
                        Label("Thermal", systemImage: "thermometer.medium")
                    }
                    NavigationLink(value: "SystemStats") {
                        Label("System Stats", systemImage: "cpu")
                    }
                    NavigationLink(value: "Caffeine") {
                        Label("Caffeine", systemImage: "cup.and.saucer")
                    }
                    NavigationLink(value: "ClaudeUsage") {
                        Label("Claude Usage", systemImage: "apple.intelligence")
                    }
                    NavigationLink(value: "Shelf") {
                        Label("Shelf", systemImage: "books.vertical")
                    }
                }

                Section("App") {
                    NavigationLink(value: "Shortcuts") {
                        Label("Shortcuts", systemImage: "keyboard")
                    }
                    NavigationLink(value: "Advanced") {
                        Label("Advanced", systemImage: "gearshape.2")
                    }
                    NavigationLink(value: "About") {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .scrollBounceBehavior(.basedOnSize)
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Displays":
                    DisplaysSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Calendar":
                    CalendarSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    Charge()
                case "Downloads":
                    Downloads()
                case "Thermal":
                    ThermalSettings()
                case "SystemStats":
                    SystemStatsSettings()
                case "Caffeine":
                    CaffeineSettings()
                case "ClaudeUsage":
                    ClaudeUsageSettings()
                case "Shelf":
                    Shelf()
                case "Shortcuts":
                    Shortcuts()
                case "Advanced":
                    Advanced()
                case "About":
                    if let ctrl = updaterController {
                        AboutSettings(updater: ctrl.updater)
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle("Launch at login")
            } header: {
                Text("System features")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("Notch height on notch displays")
                ) {
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch sizing")
            }

            NotchBehaviour()

            gestureControls()
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
                .disabled(!openNotchOnHover)
            if enableGestures {
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text(
                "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled"
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            Defaults.Toggle(key: .enableHaptics) {
                    Text("Enable haptic feedback")
            }
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show battery indicator")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Show battery percentage")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show power status icons")
                }
            } header: {
                Text("Battery Information")
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Battery")
    }
}

struct Downloads: View {
    @Default(.enableDownloadListener) var enableDownloadListener
    @Default(.enableSafariDownloads) var enableSafariDownloads
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show download progress")
                            .font(.headline)
                        Text("Monitors your Downloads folder and shows a live progress ring in the closed notch while files are downloading.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableDownloadListener)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                        .onChange(of: enableDownloadListener) { _, enabled in
                            if enabled { downloadManager.start() } else { downloadManager.stop() }
                        }
                }
                Defaults.Toggle(key: .enableSafariDownloads) {
                    Text("Monitor Safari downloads")
                }
                .disabled(!enableDownloadListener)
            } header: {
                Text("Download Monitor")
            } footer: {
                Text("Safari .download bundles show a real progress ring. Chrome .crdownload files show an indeterminate spinner until complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Downloads")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var accessibilityAuthorized = false
    @State private var showHUDCustomizer = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system HUD")
                            .font(.headline)
                        Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!accessibilityAuthorized)
                }

                if hudReplacement {
                    Button {
                        showHUDCustomizer = true
                    } label: {
                        HStack {
                            Text("Customize HUD types")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showHUDCustomizer) {
                        HUDCustomizerSheet()
                    }
                }

                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                MediaKeyInterceptor.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            
            Section {
                Picker("Option key behaviour", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                
                Picker("Progress bar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Tint progress bar with accent color")
                }
            } header: {
                Text("General")
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Show HUD in open notch")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Show percentage")
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("Open Notch")
                    customBadge(text: "Beta")
                }
            }
            .disabled(!hudReplacement)
            
            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show percentage")
                }
            } header: {
                Text("Closed Notch")
            }
            .disabled(!Defaults[.hudReplacement])

        }
        .accentColor(.effectiveAccent)
        .navigationTitle("HUDs")
        .task {
            // Poll AXIsProcessTrusted() in the main app process directly.
            // The XPC helper has its own TCC entry — checking it would always
            // return true even if the main app isn't in the Accessibility list.
            accessibilityAuthorized = AXIsProcessTrusted()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                accessibilityAuthorized = AXIsProcessTrusted()
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics
    @Default(.spectrogramTitleExclusions) var spectrogramTitleExclusions
    @Default(.spectrogramAppExclusions) var spectrogramAppExclusions
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var newTitleKeyword = ""
    @State private var isAddingTitleKeyword = false
    @State private var isAddingAppExclusion = false

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if musicManager.nowPlayingCheckFailed {
                    Text("'Now Playing' was hidden because the required framework failed to load after 5 attempts. Try restarting the app.")
                        .foregroundStyle(.red.opacity(0.8))
                        .font(.caption)
                } else if musicManager.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                } else {
                    Text(
                        "'Now Playing' was the only option on previous versions and works with all media apps."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Full screen behavior")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Hide for media app only").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
            } header: {
                Text("Live Activity")
            }

            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("Media controls")
            } footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .useResponsiveSpectrogram) {
                    Text("Responsive spectrogram")
                }
                .disabled(!Defaults[.useMusicVisualizer])
            } header: {
                Text("Spectrogram")
            } footer: {
                Text("When enabled, bars respond to actual audio content via system audio capture (requires Screen Recording permission). Disable to use the default animated spectrogram.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(spectrogramTitleExclusions, id: \.self) { keyword in
                    HStack {
                        Text(keyword)
                        Spacer()
                        Button {
                            spectrogramTitleExclusions.removeAll { $0 == keyword }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
                Button {
                    newTitleKeyword = ""
                    isAddingTitleKeyword = true
                } label: {
                    Label("Add keyword", systemImage: "plus")
                }
                .sheet(isPresented: $isAddingTitleKeyword) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Add title keyword")
                            .font(.headline)
                        TextField("e.g. Disney+", text: $newTitleKeyword)
                        HStack {
                            Spacer()
                            Button("Cancel") {
                                isAddingTitleKeyword = false
                            }
                            Button("Add") {
                                addTitleKeyword()
                                isAddingTitleKeyword = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newTitleKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .frame(minWidth: 300)
                }
            } header: {
                Text("Spectrogram exclusions — Title keywords")
            } footer: {
                Text("The responsive spectrogram is disabled when the now-playing title contains any of these words. Useful for sites like Disney+ or Netflix that pause on screen capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(spectrogramAppExclusions, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button {
                            spectrogramAppExclusions.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
                Button {
                    isAddingAppExclusion = true
                } label: {
                    Label("Add app", systemImage: "plus")
                }
                .sheet(isPresented: $isAddingAppExclusion) {
                    AppPickerSheet { bundleID in
                        if !spectrogramAppExclusions.contains(bundleID) {
                            spectrogramAppExclusions.append(bundleID)
                        }
                        isAddingAppExclusion = false
                    } onCancel: {
                        isAddingAppExclusion = false
                    }
                }
            } header: {
                Text("Spectrogram exclusions — Apps")
            } footer: {
                Text("The responsive spectrogram is disabled for these apps by bundle identifier (e.g. com.google.Chrome, com.apple.Safari).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

    private func addTitleKeyword() {
        let trimmed = newTitleKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !spectrogramTitleExclusions.contains(trimmed) else { return }
        spectrogramTitleExclusions.append(trimmed)
        newTitleKeyword = ""
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if musicManager.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct AppEntry: Identifiable {
    let id: String  // bundleID
    let name: String
    let icon: NSImage
}

struct AppPickerSheet: View {
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var apps: [AppEntry] = []
    @State private var searchText = ""
    @State private var isLoading = true

    var filtered: [AppEntry] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select App to Exclude")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                VStack {
                    ProgressView("Scanning applications…")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    Button {
                        onSelect(app.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .fontWeight(.medium)
                                Text(app.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $searchText, prompt: "Search by name or bundle ID")
            }
        }
        .frame(width: 420, height: 520)
        .task { await loadApps() }
    }

    @MainActor
    private func loadApps() async {
        let appData = await Task.detached(priority: .userInitiated) {
            AppPickerSheet.scanApps()
        }.value
        apps = appData.map { name, bundleID, path in
            AppEntry(id: bundleID, name: name, icon: NSWorkspace.shared.icon(forFile: path))
        }
        isLoading = false
    }

    nonisolated private static func scanApps() -> [(name: String, bundleID: String, path: String)] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [(name: String, bundleID: String, path: String)] = []

        let dirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for dir in dirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                seen.insert(bundleID)
                result.append((name: name, bundleID: bundleID, path: url.path))
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent

    var body: some View {
        Form {
            Defaults.Toggle(key: .showCalendar) {
                Text("Show calendar")
            }
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("Hide completed reminders")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("Hide all-day events")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("Auto-scroll to next event")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("Always show full event titles")
            }
            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Calendar access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Calendar Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Reminder access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Reminder Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Calendar")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct AboutSettings: View {
    private let updater: SPUUpdater

    @ObservedObject private var checkVM: CheckForUpdatesViewModel
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    @State private var releaseNotes: String? = nil
    @State private var isLoadingNotes = false
    @State private var showBuildNumber = false

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkVM = CheckForUpdatesViewModel(updater: updater)
        self._automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        self._automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("DynamicNotch")
                            .font(.headline)

                        Text("The Dynamic Island — but on your Mac")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Text("Version \(Bundle.main.releaseVersionNumber ?? "—")")
                                .foregroundStyle(.secondary)
                            if showBuildNumber {
                                Text("(\(Bundle.main.buildVersionNumber ?? "—"))")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        .onTapGesture {
                            withAnimation { showBuildNumber.toggle() }
                        }

                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }

                Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                        updater.automaticallyDownloadsUpdates = newValue
                    }

                HStack {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.effectiveAccent)
                    .disabled(!checkVM.canCheckForUpdates)
                    Spacer()
                }
            } header: {
                Text("Software Updates")
            }

            Section {
                if isLoadingNotes {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 8)
                        Spacer()
                    }
                } else if let notes = releaseNotes, !notes.isEmpty {
                    Group {
                        if let attributed = try? AttributedString(
                            markdown: notes,
                            options: AttributedString.MarkdownParsingOptions(
                                interpretedSyntax: .inlineOnlyPreservingWhitespace
                            )
                        ) {
                            Text(attributed)
                        } else {
                            Text(notes)
                        }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Release notes unavailable.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("What's New in \(Bundle.main.releaseVersionNumber ?? "—")")
                    Spacer()
                    Button("All Releases") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/Hitjack007/DynamicNotch/releases")!)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Repository") {
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/Hitjack007/DynamicNotch")!)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.effectiveAccent)
                }
                LabeledContent("Feedback") {
                    Button("Report an Issue") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/Hitjack007/DynamicNotch/issues/new")!)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.effectiveAccent)
                }
            } header: {
                Text("Links")
            }
        }
        .navigationTitle("About")
        .accentColor(.effectiveAccent)
        .task { await fetchReleaseNotes() }
    }

    @MainActor
    private func fetchReleaseNotes() async {
        guard let version = Bundle.main.releaseVersionNumber else { return }
        isLoadingNotes = true
        defer { isLoadingNotes = false }

        let tag = "v\(version)"
        guard let url = URL(string: "https://api.github.com/repos/Hitjack007/DynamicNotch/releases/tags/\(tag)") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["body"] as? String else { return }

        releaseNotes = body
    }
}

struct Shelf: View {

    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @Default(.shelfItemExpiry) var shelfItemExpiry: ShelfItemExpiry
    @Default(.clipboardHistoryEnabled) var clipboardHistoryEnabled: Bool
    @Default(.clipboardHistoryLimit) var clipboardHistoryLimit: Int
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }
    
    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("Enable shelf")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }
                Picker("Auto-delete items after", selection: $shelfItemExpiry) {
                    ForEach(ShelfItemExpiry.allCases) { expiry in
                        Text(expiry.rawValue).tag(expiry)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: shelfItemExpiry) {
                    ShelfStateViewModel.shared.cleanupExpiredItems()
                }

            } header: {
                HStack {
                    Text("General")
                }
            }
            
            Section {
                Picker("Quick Share Service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Currently selected: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Providers are always enabled; user can pick default service above.

            } header: {
                HStack {
                    Text("Quick Share")
                }
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Defaults.Toggle(key: .clipboardHistoryEnabled) {
                    Text("Capture clipboard history")
                }
                if clipboardHistoryEnabled {
                    Picker("Maximum items", selection: $clipboardHistoryLimit) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("Unlimited").tag(0)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: clipboardHistoryLimit) {
                        ShelfStateViewModel.shared.trimClipboardHistory()
                    }
                    Button("Clear clipboard history", role: .destructive) {
                        ShelfStateViewModel.shared.clearClipboardHistory()
                    }
                }
            } header: {
                Text("Clipboard History")
            } footer: {
                Text("Automatically captures text, links, and images you copy. Items appear in the shelf with a clipboard badge.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
    }
}

//struct Extensions: View {
//    @State private var effectTrigger: Bool = false
//    var body: some View {
//        Form {
//            Section {
//                List {
//                    ForEach(extensionManager.installedExtensions.indices, id: \.self) { index in
//                        let item = extensionManager.installedExtensions[index]
//                        HStack {
//                            AppIcon(for: item.bundleIdentifier)
//                                .resizable()
//                                .frame(width: 24, height: 24)
//                            Text(item.name)
//                            ListItemPopover {
//                                Text("Description")
//                            }
//                            Spacer(minLength: 0)
//                            HStack(spacing: 6) {
//                                Circle()
//                                    .frame(width: 6, height: 6)
//                                    .foregroundColor(
//                                        isExtensionRunning(item.bundleIdentifier)
//                                            ? .green : item.status == .disabled ? .gray : .red
//                                    )
//                                    .conditionalModifier(isExtensionRunning(item.bundleIdentifier))
//                                { view in
//                                    view
//                                        .shadow(color: .green, radius: 3)
//                                }
//                                Text(
//                                    isExtensionRunning(item.bundleIdentifier)
//                                        ? "Running"
//                                        : item.status == .disabled ? "Disabled" : "Stopped"
//                                )
//                                .contentTransition(.numericText())
//                                .foregroundStyle(.secondary)
//                                .font(.footnote)
//                            }
//                            .frame(width: 60, alignment: .leading)
//
//                            Menu(
//                                content: {
//                                    Button("Restart") {
//                                        let ws = NSWorkspace.shared
//
//                                        if let ext = ws.runningApplications.first(where: {
//                                            $0.bundleIdentifier == item.bundleIdentifier
//                                        }) {
//                                            ext.terminate()
//                                        }
//
//                                        if let appURL = ws.urlForApplication(
//                                            withBundleIdentifier: item.bundleIdentifier)
//                                        {
//                                            ws.openApplication(
//                                                at: appURL, configuration: .init(),
//                                                completionHandler: nil)
//                                        }
//                                    }
//                                    .keyboardShortcut("R", modifiers: .command)
//                                    Button("Disable") {
//                                        if let ext = NSWorkspace.shared.runningApplications.first(
//                                            where: { $0.bundleIdentifier == item.bundleIdentifier })
//                                        {
//                                            ext.terminate()
//                                        }
//                                        extensionManager.installedExtensions[index].status =
//                                            .disabled
//                                    }
//                                    .keyboardShortcut("D", modifiers: .command)
//                                    Divider()
//                                    Button("Uninstall", role: .destructive) {
//                                        //
//                                    }
//                                },
//                                label: {
//                                    Image(systemName: "ellipsis.circle")
//                                        .foregroundStyle(.secondary)
//                                }
//                            )
//                            .controlSize(.regular)
//                        }
//                        .buttonStyle(PlainButtonStyle())
//                        .padding(.vertical, 5)
//                    }
//                }
//                .frame(minHeight: 120)
//                .actionBar {
//                    Button {
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "plus")
//                            Text("Add manually")
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                    .disabled(true)
//                    Spacer()
//                    Button {
//                        withAnimation(.linear(duration: 1)) {
//                            effectTrigger.toggle()
//                        } completion: {
//                            effectTrigger.toggle()
//                        }
//                        extensionManager.checkIfExtensionsAreInstalled()
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "arrow.triangle.2.circlepath")
//                                .rotationEffect(effectTrigger ? .degrees(360) : .zero)
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                }
//                .controlSize(.small)
//                .buttonStyle(PlainButtonStyle())
//                .overlay {
//                    if extensionManager.installedExtensions.isEmpty {
//                        Text("No extension installed")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                            .padding(.bottom, 22)
//                    }
//                }
//            } header: {
//                HStack(spacing: 0) {
//                    Text("Installed extensions")
//                    if !extensionManager.installedExtensions.isEmpty {
//                        Text(" – \(extensionManager.installedExtensions.count)")
//                            .foregroundStyle(.secondary)
//                    }
//                }
//            }
//        }
//        .accentColor(.effectiveAccent)
//        .navigationTitle("Extensions")
//        // TipsView()
//        // .padding(.horizontal, 19)
//    }
//}

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }

            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Media")
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable boring mirror")
                }
                    .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
            } header: {
                HStack {
                    Text("Additional features")
                }
            } footer: {
                Text("Live activities and idle widgets are now configured per-display in the Displays section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

// MARK: - Displays Settings

struct DisplaysSettings: View {
    @State private var screens: [(uuid: String, name: String)] = []
    @State private var selectedUUID: String = ""
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Fall back to main display if preferred is unavailable")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
                Picker("Show HUD on", selection: Binding(
                    get: { Defaults[.hudDisplayPolicy] },
                    set: { Defaults[.hudDisplayPolicy] = $0 }
                )) {
                    ForEach(HUDDisplayPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!showOnAllDisplays)
            } header: {
                Text("Multi-Display")
            }

            Section {
                if screens.count > 1 {
                    Picker("Configure for", selection: $selectedUUID) {
                        ForEach(screens, id: \.uuid) { screen in
                            Text(screen.name).tag(screen.uuid)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Per-Display Settings")
            }

            if !selectedUUID.isEmpty {
                PerDisplaySettings(screenUUID: selectedUUID)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Displays")
        .onAppear { refreshScreens() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            Task { @MainActor in
                // Small delay so Sidecar/AirPlay has time to resolve its display name
                try? await Task.sleep(for: .milliseconds(500))
                refreshScreens()
            }
        }
    }

    private func refreshScreens() {
        screens = NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            return (uuid, screen.localizedName)
        }
        if selectedUUID.isEmpty || !screens.map(\.uuid).contains(selectedUUID) {
            selectedUUID = screens.first?.uuid ?? ""
        }
    }
}

struct PerDisplaySettings: View {
    let screenUUID: String
    @Default(.perScreenConfigs) private var perScreenConfigs

    private var config: PerScreenConfig {
        Defaults[.perScreenConfigs][screenUUID] ?? PerScreenConfig()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<PerScreenConfig, T>) -> Binding<T> {
        Binding(
            get: { Defaults[.perScreenConfigs][screenUUID]?[keyPath: keyPath]
                    ?? PerScreenConfig()[keyPath: keyPath] },
            set: { newValue in
                var c = Defaults[.perScreenConfigs][screenUUID] ?? PerScreenConfig()
                c[keyPath: keyPath] = newValue
                Defaults[.perScreenConfigs][screenUUID] = c
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Music live activity", isOn: binding(\.musicLiveActivityEnabled))
            Toggle("Download live activity", isOn: binding(\.downloadLiveActivityEnabled))
            Toggle("Face animation while idle", isOn: binding(\.showFaceAnimation))
            Toggle("Claude usage indicator", isOn: binding(\.claudeUsageInNotch))
        } header: {
            Text("Live Activities")
        } footer: {
            Text("Controls what appears in the closed notch on this display.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            IdleWidgetConfigurationView(
                leftWidget: binding(\.idleLeftWidget),
                rightWidget: binding(\.idleRightWidget)
            )
        } header: {
            Text("Idle Widgets")
        } footer: {
            Text("Shown when nothing is playing and no live activity is active.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct Advanced: View {
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil

    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"
        
        var id: String { self.rawValue }
        
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between system and custom
                    Picker("Accent color", selection: $useCustomAccentColor) {
                        Text("System").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if !useCustomAccentColor {
                        // System accent info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentCircleButton(
                                    isSelected: true,
                                    color: .accentColor,
                                    isSystemDefault: true
                                ) {}
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Using System Accent")
                                        .font(.body)
                                    Text("Your macOS system accent color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // Custom color options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color Presets")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Custom color picker
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pick a Color")
                                        .font(.body)
                                    Text("Choose any color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    ZStack {
                                        Circle()
                                            .fill(customAccentColor)
                                            .frame(width: 32, height: 32)
                                        
                                        if selectedPresetColor == nil {
                                            Circle()
                                                .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent color")
            } footer: {
                Text("Choose between your system accent color or customize it with your own selection.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .onAppear {
                initializeAccentColorState()
            }
            
            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
            } header: {
                Text("Window Appearance")
            }
            
            Section {
                Defaults.Toggle(key: .extendHoverArea) {
                    Text("Extend hover area")
                }
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Hide title bar")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window Behavior")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Advanced")
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }
    
    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            
            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }
    
    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
    
    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            } header: {
                Text("Notch")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

struct HUDCustomizerSheet: View {
    @Default(.hudVolume) var hudVolume
    @Default(.hudBrightness) var hudBrightness
    @Default(.hudBacklight) var hudBacklight
    // TODO: Add "Microphone Mute" toggle here (using Defaults[.hudMic]) once mic mute
    // detection is wired up — see sneakPeekEvent in BoringViewCoordinator.swift.
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HUD Types")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            Form {
                Toggle("Volume", isOn: $hudVolume)
                Toggle("Display Brightness", isOn: $hudBrightness)
                Toggle("Keyboard Brightness", isOn: $hudBacklight)

                Button("Reset to Defaults") {
                    hudVolume = true
                    hudBrightness = true
                    hudBacklight = true
                }
                .foregroundStyle(.red)
            }
            .formStyle(.grouped)
        }
        .frame(width: 340, height: 280)
    }
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct ThermalSettings: View {
    @Default(.showThermalTab) var showThermalTab
    @Default(.thermalAlertEnabled) var thermalAlertEnabled
    @Default(.thermalAlertThreshold) var thermalAlertThreshold
    @Default(.fanCurveEnabled) var fanCurveEnabled
    @Default(.fanCurvePoints) var fanCurvePoints
    @Default(.fanCurvePreset) var fanCurvePreset
    @Default(.thermalNotchPresets) var thermalNotchPresets

    @State private var daemonAvailable: Bool = false
    @State private var hasFans: Bool = true
    @State private var showTerminalInstructions: Bool = false
    @State private var installError: String? = nil

    var body: some View {
        Form {
            Section {
                Toggle("Show Thermal tab", isOn: $showThermalTab)
            } header: {
                Text("Display")
            } footer: {
                Text("Adds a Thermal tab to the open notch showing live CPU, GPU, and fan data.")
            }

            Section {
                Toggle("Alert when temperature is high", isOn: $thermalAlertEnabled)
                if thermalAlertEnabled {
                    Stepper(
                        "Alert threshold: \(thermalAlertThreshold)°C",
                        value: $thermalAlertThreshold,
                        in: 70...100,
                        step: 5
                    )
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Shows a brief orange strip in the closed notch when peak CPU or GPU temperature exceeds the threshold. Alerts are rate-limited to once per minute.")
            }
            .disabled(!showThermalTab)

            Section {
                if !hasFans {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not available on this Mac")
                                .font(.subheadline)
                            Text("Fan curve control requires fans. This Mac is fanless.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } else {
                    // Daemon status row
                    HStack(spacing: 8) {
                        Circle()
                            .fill(daemonAvailable ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(daemonAvailable ? "Fan daemon running" : "Fan daemon not installed")
                            .foregroundStyle(daemonAvailable ? .primary : .secondary)
                        Spacer()
                        if !daemonAvailable {
                            if showTerminalInstructions {
                                HStack(spacing: 6) {
                                    Button("Check again") { checkDaemon() }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    Button { showTerminalInstructions = false } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                }
                            } else {
                                Button("Setup…") { installDaemon() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                        } else {
                            Button("Reinstall") { installDaemon() }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showTerminalInstructions {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Command copied to clipboard.")
                                .font(.caption).bold()
                            Text("In Terminal, press ⌘V then Enter. Takes ~15s to compile. After it finishes, click Check again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !daemonAvailable {
                                Text("Still not detected? Run in Terminal: sudo launchctl list com.boringnotch.thermaldaemon")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let err = installError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Fan Curve", selection: $fanCurvePreset) {
                        ForEach(FanCurvePreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .disabled(!daemonAvailable)
                    .onChange(of: fanCurvePreset) {
                        applyPreset(fanCurvePreset)
                    }

                    LabeledContent("Presets in notch") {
                        Text("up to 3")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    ForEach(FanCurvePreset.allCases) { preset in
                        Toggle(preset.rawValue, isOn: Binding(
                            get: { thermalNotchPresets.contains(preset) },
                            set: { on in
                                if on {
                                    guard thermalNotchPresets.count < 3 else { return }
                                    thermalNotchPresets.append(preset)
                                } else {
                                    thermalNotchPresets.removeAll { $0 == preset }
                                }
                            }
                        ))
                        .disabled(!thermalNotchPresets.contains(preset) && thermalNotchPresets.count >= 3)
                    }

                    if fanCurvePreset == .custom && daemonAvailable {
                        VStack(alignment: .leading, spacing: 10) {
                            FanCurveEditorView()

                            HStack {
                                Text("Tap to add · Right-click to remove · Drag to move · 2–5 points")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset") {
                                    fanCurvePoints = FanCurvePoint.defaultCurve
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Fan Curve")
            } footer: {
                if hasFans {
                    Text("The daemon runs as root so SMC fan writes succeed on all Apple Silicon Macs. It's installed once to /Library/BoringNotch/ and auto-starts on login. The fan curve is evaluated every 2 seconds; fans restore to Apple automatic control when boring.notch quits.")
                }
            }
            .disabled(!showThermalTab)
        }
        .formStyle(.grouped)
        .onAppear {
            daemonAvailable = ThermalDaemonClient.shared.checkAvailability()
            hasFans = ThermalManager.shared.detectHasFans()
            // Migrate: if fan curve was previously enabled but no preset was stored
            if fanCurveEnabled && fanCurvePreset == .appleDefault {
                fanCurvePreset = .custom
            }
        }
    }

    private func applyPreset(_ preset: FanCurvePreset) {
        switch preset {
        case .appleDefault:
            fanCurveEnabled = false
        case .maxSpeed:
            fanCurveEnabled = false
        case .custom:
            fanCurveEnabled = true
        case .ramp80, .ramp70, .ramp60:
            if let pts = preset.curvePoints {
                fanCurvePoints = pts
            }
            fanCurveEnabled = true
        }
    }

    private func installDaemon() {
        guard let resourcePath = Bundle.main.resourcePath else {
            installError = "Could not locate app resources."
            return
        }
        let scriptPath = (resourcePath as NSString).appendingPathComponent("install-thermal-daemon.sh")
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            installError = "Script not found — add install-thermal-daemon.sh to Copy Bundle Resources in Xcode."
            return
        }
        // The App Sandbox blocks privileged AppleScript execution. Instead, copy the
        // sudo commands to clipboard and open Terminal so the user can run them directly.
        // Kill the old daemon first (bootout for macOS 13+, pkill as fallback), then install fresh.
        let killCmd = "sudo launchctl bootout system/com.boringnotch.thermaldaemon 2>/dev/null; sudo pkill -f BoringNotchThermalDaemon 2>/dev/null; sleep 1"
        let cmd = "\(killCmd) && sudo bash '\(scriptPath)'"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        installError = nil
        showTerminalInstructions = true
    }

    private func checkDaemon() {
        daemonAvailable = ThermalDaemonClient.shared.checkAvailability()
        ThermalManager.shared.daemonAvailable = daemonAvailable
        if daemonAvailable { showTerminalInstructions = false }
    }
}

struct CaffeineSettings: View {
    @Default(.showCaffeineButton)      var showCaffeineButton
    @Default(.caffeineDefaultDuration) var caffeineDefaultDuration
    @Default(.caffeineKeepAppsActive)  var caffeineKeepAppsActive
    @ObservedObject var caffeineManager = CaffeineManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show Caffeine button in notch", isOn: $showCaffeineButton)
                    .onChange(of: showCaffeineButton) { _, enabled in
                        if !enabled {
                            caffeineManager.deactivate()
                        }
                    }
            } header: {
                Text("Display")
            } footer: {
                Text("Adds a coffee cup button to the open notch. Click it to prevent your Mac from sleeping.")
            }

            Section {
                Picker("Activate for", selection: $caffeineDefaultDuration) {
                    Text("Indefinitely").tag(0)
                    Text("30 minutes").tag(30 * 60)
                    Text("1 hour").tag(60 * 60)
                    Text("2 hours").tag(2 * 60 * 60)
                    Text("4 hours").tag(4 * 60 * 60)
                    Text("5 hours").tag(5 * 60 * 60)
                }
            } header: {
                Text("Duration")
            } footer: {
                Text("How long Caffeine stays active after tapping the notch button. When the Mac goes to sleep it always deactivates automatically.")
            }
            .disabled(!showCaffeineButton)

            Section {
                Toggle("Keep apps active", isOn: Binding(
                    get: { caffeineKeepAppsActive },
                    set: { newValue in
                        caffeineKeepAppsActive = newValue
                        caffeineManager.updateActivitySimulation(enabled: newValue)
                    }
                ))
            } header: {
                Text("Presence")
            } footer: {
                Text("Simulates mouse activity every 30 seconds when the system has been idle for 90 seconds, keeping apps like Teams and Slack from showing you as Away. Requires Accessibility permission.")
            }
            .disabled(!showCaffeineButton)
        }
        .formStyle(.grouped)
    }
}

struct SystemStatsSettings: View {
    @Default(.showSystemStatsTab) var showSystemStatsTab
    @Default(.showStatsCPU)       var showStatsCPU
    @Default(.showStatsRAM)       var showStatsRAM
    @Default(.showStatsSwap)      var showStatsSwap

    var body: some View {
        Form {
            Section {
                Toggle("Show System Stats tab", isOn: $showSystemStatsTab)
            } header: {
                Text("Display")
            } footer: {
                Text("Adds a System Stats tab to the open notch showing live CPU usage, RAM, and swap.")
            }

            Section {
                Toggle("CPU usage", isOn: $showStatsCPU)
                Toggle("RAM usage", isOn: $showStatsRAM)
                Toggle("Swap usage", isOn: $showStatsSwap)
            } header: {
                Text("Metrics")
            } footer: {
                Text("Choose which metrics to display. Swap is automatically hidden if your Mac reports no swap.")
            }
            .disabled(!showSystemStatsTab)
        }
        .formStyle(.grouped)
    }
}

struct ClaudeUsageSettings: View {
    @Default(.showClaudeUsageTab)         var showClaudeUsageTab
    @Default(.claudeUsageInNotch)         var claudeUsageInNotch
    @Default(.claudeClosedNotchShowRing)  var claudeClosedNotchShowRing
    @Default(.claudePreferredBrowser)     var claudePreferredBrowser
    @Default(.claudePollingInterval)      var claudePollingInterval
    @ObservedObject var manager = ClaudeUsageManager.shared

    @State private var hasFullDiskAccess = false
    @State private var manualSessionKey = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable Claude Usage", isOn: $showClaudeUsageTab)
            } header: {
                Text("Display")
            } footer: {
                Text("Adds a Claude Usage tab to the open notch. Log into Claude in your browser first, then authenticate below.")
            }

            Section {
                Toggle("Show in closed notch", isOn: $claudeUsageInNotch)
                Picker("Left indicator", selection: $claudeClosedNotchShowRing) {
                    Text("Progress ring").tag(true)
                    Text("Percentage").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(!claudeUsageInNotch)
            } header: {
                Text("Closed Notch")
            } footer: {
                Text("Shows usage on the left and time until reset on the right. Volume, music, and live activities take priority.")
            }
            .disabled(!showClaudeUsageTab)

            Section {
                Picker("Browser", selection: $claudePreferredBrowser) {
                    ForEach(ClaudeBrowserPreference.allCases) { browser in
                        Text(browser.rawValue).tag(browser)
                    }
                }
                Picker("Polling interval", selection: $claudePollingInterval) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
            } header: {
                Text("Configuration")
            }
            .disabled(!showClaudeUsageTab)

            Section {
                authStatusRow

                HStack(spacing: 12) {
                    if manager.isAuthenticated {
                        Button("Re-authenticate") {
                            Task { await manager.reauthenticate() }
                        }
                    } else {
                        Button("Authenticate from Browser") {
                            Task { await manager.authenticate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.effectiveAccent)
                    }
                    if manager.isAuthenticating {
                        ProgressView().controlSize(.small)
                    }
                }

                HStack {
                    Image(systemName: hasFullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(hasFullDiskAccess ? .green : .orange)
                    Text(hasFullDiskAccess ? "Full Disk Access granted" : "Full Disk Access required for auto-detect")
                        .foregroundStyle(hasFullDiskAccess ? .primary : .secondary)
                    Spacer()
                    if !hasFullDiskAccess {
                        Button("Grant…") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let fetched = manager.lastFetched {
                    Text("Last updated \(fetched.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Reads your browser session cookie directly — no password stored. Requires Full Disk Access to detect the cookie automatically.")
            }
            .disabled(!showClaudeUsageTab)

            Section {
                TextField("sk-ant-sid02-…", text: $manualSessionKey)
                    .font(.system(.caption, design: .monospaced))
                Button("Save Session Key") {
                    Task {
                        await manager.authenticateManually(sessionKey: manualSessionKey)
                        manualSessionKey = ""
                    }
                }
                .disabled(manualSessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isAuthenticating)
            } header: {
                Text("Manual Entry")
            } footer: {
                Text("If auto-detect fails, open claude.ai → DevTools (⌥⌘I) → Application → Cookies → copy the value of 'sessionKey' and paste it above.")
            }
            .disabled(!showClaudeUsageTab)
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .navigationTitle("Claude Usage")
        .task {
            hasFullDiskAccess = checkFullDiskAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = checkFullDiskAccess()
        }
    }

    private func checkFullDiskAccess() -> Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileManager.default.isReadableFile(atPath: path)
    }

    @ViewBuilder
    private var authStatusRow: some View {
        HStack(spacing: 8) {
            switch manager.authState {
            case .unauthenticated:
                Image(systemName: "person.slash").foregroundStyle(.secondary)
                Text("Not authenticated").foregroundStyle(.secondary)
            case .authenticated:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Authenticated")
            case .expired:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("Session expired — re-authenticate").foregroundStyle(.orange)
            case .error(let msg):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(msg).foregroundStyle(.red).lineLimit(2)
            }
        }
    }
}

#Preview {
    HUD()
}
