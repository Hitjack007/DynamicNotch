//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Mark Greene on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    @Published var isAudioPickerActive: Bool = false

    @Published var screenUUID: String?
    @Published var screenConfig: PerScreenConfig = PerScreenConfig()

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()

        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)

        setupScreenConfig()
        setupDetectorObserver()
    }

    // MARK: - Per-screen config

    /// True when this screen should follow the global feature-section settings
    /// instead of a per-display override: the primary (menu-bar) display, or any
    /// screen at all when the app isn't showing a notch on every display (in
    /// single-display mode there's nothing to "override" against).
    private var usesGlobalConfig: Bool {
        guard let uuid = screenUUID else { return true }
        return !Defaults[.showOnAllDisplays] || uuid == NSScreen.primaryDisplayUUID
    }

    private func recomputeScreenConfig() {
        guard !usesGlobalConfig, let uuid = screenUUID else {
            screenConfig = .fromGlobalSettings
            return
        }
        screenConfig = Defaults[.perScreenConfigs][uuid] ?? .fromGlobalSettings
    }

    private func setupScreenConfig() {
        // screenUUID starts nil for the single-display-mode view model (it's
        // assigned after the window is created), so seeding/subscribing has to
        // react to the published property rather than an init-time parameter —
        // otherwise this screen's config never leaves the struct default and
        // per-display toggles silently do nothing.
        $screenUUID
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] uuid in
                guard let self = self else { return }

                // Seed a per-display override the first time a non-primary screen is
                // seen, so there's something to edit if the user opens Displays →
                // Per-Display Settings. The primary display never gets one — it
                // always tracks global settings live.
                if uuid != NSScreen.primaryDisplayUUID, Defaults[.perScreenConfigs][uuid] == nil {
                    Defaults[.perScreenConfigs][uuid] = .fromGlobalSettings
                }
                self.recomputeScreenConfig()
            }
            .store(in: &cancellables)

        Defaults.publisher(.perScreenConfigs)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recomputeScreenConfig()
            }
            .store(in: &cancellables)

        // The primary display (and single-display mode) reads live activity and
        // idle widget settings straight from their feature sections rather than a
        // frozen per-display copy — react live as those change.
        Task { @MainActor [weak self] in
            for await _ in Defaults.updates(PerScreenConfig.globalSourceKeys) {
                self?.recomputeScreenConfig()
            }
        }
    }

    func updateScreenConfig(_ update: (inout PerScreenConfig) -> Void) {
        guard let uuid = screenUUID else { return }
        var config = Defaults[.perScreenConfigs][uuid] ?? .fromGlobalSettings
        update(&config)
        Defaults[.perScreenConfigs][uuid] = config
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        self.notchSize = openNotchSize
        self.notchState = .open
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.isAudioPickerActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
    if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
