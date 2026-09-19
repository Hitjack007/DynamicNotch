//
//  ExtensionEventBus.swift
//  boringNotch
//
//  Subscribes to every existing manager's own publishers/notifications and
//  normalizes them into ExtensionTriggerEvent, one function per TriggerID
//  group (see CapabilityRegistry's `implementedBy` for the mapping). This
//  deliberately does not modify any existing manager — it only observes
//  state that's already `@Published` or already posted via NotificationCenter,
//  so the extensions system can be lifted out cleanly if it's ever reworked.
//
//  Nothing subscribes to `eventPublisher` yet — the rule-matching engine that
//  reads stored extensions and decides which ones to fire is a separate,
//  later piece of work. This bus is the "triggers actually happen" layer on
//  its own.
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class ExtensionEventBus: ObservableObject {
    static let shared = ExtensionEventBus()

    let eventPublisher = PassthroughSubject<ExtensionTriggerEvent, Never>()
    @Published private(set) var lastEvent: ExtensionTriggerEvent?

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    // Diffing state
    private var announcedUpcomingEventIDs: Set<String> = []
    private var wasInMeeting = false
    private var previousDownloadIDs: Set<UUID> = []
    private var knownDisplayUUIDs: Set<String> = Set(NSScreen.screens.compactMap(\.displayUUID))
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount

    private var calendarTimer: Timer?
    private var tickTimer: Timer?
    private var clipboardPollTask: Task<Void, Never>?

    private init() {}

    /// Idempotent — safe to call multiple times (e.g. from the app delegate).
    func start() {
        guard !started else { return }
        started = true

        observeBattery()
        observeVolume()
        observeBrightness()
        observeMedia()
        observeCalendar()
        observeThermal()
        observeAudioDevice()
        observeBluetoothBattery()
        observeClipboard()
        observeDownloads()
        observeAIUsage()
        observeCaffeine()
        observeSleepWake()
        observeAppLifecycle()
        observeTimeTick()
        observeDisplays()
        observeWebcam()
        observeAirPlay()
    }

    private func emit(_ id: TriggerID, _ payload: [String: ExtensionValue] = [:]) {
        let event = ExtensionTriggerEvent(id: id, payload: payload)
        lastEvent = event
        eventPublisher.send(event)
    }

    // MARK: - Battery

    func observeBattery() {
        _ = BatteryActivityManager.shared.addObserver { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case .batteryLevelChanged(let level):
                    self.emit(.batteryLevelChanged, ["level": .int(Int(level))])
                case .isChargingChanged(let isCharging):
                    self.emit(.batteryChargingChanged, ["isCharging": .bool(isCharging)])
                case .lowPowerModeChanged(let isEnabled):
                    self.emit(.batteryLowPowerModeChanged, ["enabled": .bool(isEnabled)])
                default:
                    break
                }
            }
        }
    }

    // MARK: - Volume / Brightness

    func observeVolume() {
        VolumeManager.shared.$rawVolume
            .combineLatest(VolumeManager.shared.$isMuted)
            .dropFirst()
            .sink { [weak self] level, muted in
                self?.emit(.volumeChanged, ["level": .double(Double(level)), "muted": .bool(muted)])
            }
            .store(in: &cancellables)
    }

    func observeBrightness() {
        BrightnessManager.shared.$rawBrightness
            .dropFirst()
            .sink { [weak self] level in
                self?.emit(.brightnessChanged, ["level": .double(Double(level))])
            }
            .store(in: &cancellables)
    }

    // MARK: - Media

    func observeMedia() {
        MusicManager.shared.$isPlaying
            .dropFirst()
            .sink { [weak self] isPlaying in
                let mm = MusicManager.shared
                self?.emit(.mediaPlaybackChanged, [
                    "isPlaying": .bool(isPlaying),
                    "title": .string(mm.songTitle),
                    "artist": .string(mm.artistName),
                    "bundleIdentifier": .string(mm.bundleIdentifier ?? ""),
                ])
            }
            .store(in: &cancellables)

        MusicManager.shared.$songTitle
            .combineLatest(MusicManager.shared.$artistName)
            .dropFirst()
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] title, artist in
                self?.emit(.mediaTrackChanged, ["title": .string(title), "artist": .string(artist)])
            }
            .store(in: &cancellables)
    }

    // MARK: - Calendar

    func observeCalendar() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickCalendar() }
        }
        RunLoop.main.add(timer, forMode: .common)
        calendarTimer = timer
        tickCalendar()
    }

    func tickCalendar() {
        let now = Date()
        let events = CalendarManager.shared.events

        let inMeeting = events.contains { $0.isMeeting && $0.start <= now && $0.end > now }
        if inMeeting != wasInMeeting {
            wasInMeeting = inMeeting
            emit(.calendarInMeetingChanged, ["inMeeting": .bool(inMeeting)])
        }

        let leadTime: TimeInterval = 5 * 60
        for event in events {
            let secondsUntilStart = event.start.timeIntervalSince(now)
            guard secondsUntilStart > 0, secondsUntilStart <= leadTime else { continue }
            guard !announcedUpcomingEventIDs.contains(event.id) else { continue }
            announcedUpcomingEventIDs.insert(event.id)
            emit(.calendarEventStartingSoon, [
                "title": .string(event.title),
                "minutesUntilStart": .int(Int(secondsUntilStart / 60)),
            ])
        }
        // Drop bookkeeping for events that are no longer in the fetched window.
        announcedUpcomingEventIDs.formIntersection(Set(events.map(\.id)))
    }

    // MARK: - Thermal

    func observeThermal() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                let name = Self.thermalStateName(ProcessInfo.processInfo.thermalState)
                self?.emit(.thermalStateChanged, ["state": .string(name)])
            }
        }
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Audio device / Bluetooth battery

    func observeAudioDevice() {
        AudioOutputManager.shared.$currentDeviceID
            .dropFirst()
            .sink { [weak self] deviceID in
                let name = AudioOutputManager.shared.outputDevices
                    .first(where: { $0.id == deviceID })?.name ?? "Unknown"
                self?.emit(.audioDeviceChanged, ["deviceName": .string(name)])
            }
            .store(in: &cancellables)
    }

    func observeBluetoothBattery() {
        BluetoothBatteryManager.shared.start()
        BluetoothBatteryManager.shared.$connectedAudioDevices
            .dropFirst()
            .sink { [weak self] devices in
                guard let primary = devices.first else { return }
                self?.emit(.bluetoothDeviceBatteryChanged, [
                    "deviceName": .string(primary.name),
                    "batteryLevel": .int(primary.batteryLevel),
                ])
            }
            .store(in: &cancellables)
    }

    // MARK: - Clipboard
    // Polls independently of ClipboardManager (which only forwards captured
    // items into the shelf and has no external "did capture" hook) so this
    // stays decoupled from shelf/clipboard-history behavior.

    func observeClipboard() {
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        clipboardPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { break }
                self?.pollClipboard()
            }
        }
    }

    func pollClipboard() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = count
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        emit(.clipboardChanged, ["text": .string(text)])
    }

    // MARK: - Downloads

    func observeDownloads() {
        DownloadManager.shared.$activeDownloads
            .sink { [weak self] downloads in
                guard let self else { return }
                let currentIDs = Set(downloads.map(\.id))
                let started = currentIDs.subtracting(self.previousDownloadIDs)
                let completed = self.previousDownloadIDs.subtracting(currentIDs)

                for id in started {
                    if let download = downloads.first(where: { $0.id == id }) {
                        self.emit(.downloadStarted, ["fileName": .string(download.fileName)])
                    }
                }
                for _ in completed {
                    self.emit(.downloadCompleted)
                }
                self.previousDownloadIDs = currentIDs
            }
            .store(in: &cancellables)
    }

    // MARK: - AI usage

    func observeAIUsage() {
        Defaults.publisher(.aiUsageThresholdState)
            .sink { [weak self] change in
                guard let self else { return }
                let old = change.oldValue
                let new = change.newValue

                if new.lastNotifiedThreshold > old.lastNotifiedThreshold {
                    self.emit(.aiUsageThresholdCrossed, [
                        "threshold": .int(new.lastNotifiedThreshold),
                        "provider": .string(AIUsageCoordinator.shared.activeSource.displayName),
                    ])
                }
                if old.peakPercent > 0, new.peakPercent == 0 {
                    self.emit(.aiUsageWindowReset, ["previousPeak": .double(old.peakPercent)])
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Caffeine

    func observeCaffeine() {
        CaffeineManager.shared.$isActive
            .dropFirst()
            .sink { [weak self] isActive in
                self?.emit(.caffeineStateChanged, ["isActive": .bool(isActive)])
            }
            .store(in: &cancellables)
    }

    // MARK: - Sleep / Wake

    func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.emit(.sleepWillSleep) }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.emit(.sleepDidWake) }
        }
    }

    // MARK: - App lifecycle

    func observeAppLifecycle() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.emit(.appFrontmostChanged, [
                    "bundleIdentifier": .string(app.bundleIdentifier ?? ""),
                    "name": .string(app.localizedName ?? ""),
                ])
            }
        }
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.emit(.appLaunched, [
                    "bundleIdentifier": .string(app.bundleIdentifier ?? ""),
                    "name": .string(app.localizedName ?? ""),
                ])
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.emit(.appTerminated, [
                    "bundleIdentifier": .string(app.bundleIdentifier ?? ""),
                    "name": .string(app.localizedName ?? ""),
                ])
            }
        }
    }

    // MARK: - Time

    func observeTimeTick() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emit(.timeTick, ["epochSeconds": .int(Int(Date().timeIntervalSince1970))])
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: - Displays

    func observeDisplays() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickDisplays() }
        }
    }

    func tickDisplays() {
        let current = Set(NSScreen.screens.compactMap(\.displayUUID))
        let connected = current.subtracting(knownDisplayUUIDs)
        let disconnected = knownDisplayUUIDs.subtracting(current)
        for uuid in connected { emit(.displayConnected, ["displayUUID": .string(uuid)]) }
        for uuid in disconnected { emit(.displayDisconnected, ["displayUUID": .string(uuid)]) }
        knownDisplayUUIDs = current
    }

    // MARK: - Webcam

    func observeWebcam() {
        WebcamManager.shared.$isSessionRunning
            .dropFirst()
            .sink { [weak self] isRunning in
                self?.emit(.webcamActiveChanged, ["isActive": .bool(isRunning)])
            }
            .store(in: &cancellables)
    }

    // MARK: - AirPlay

    func observeAirPlay() {
        AirPlayConnector.shared.$connectingDevices
            .dropFirst()
            .sink { [weak self] devices in
                self?.emit(.airplayConnectingChanged, ["connectingCount": .int(devices.count)])
            }
            .store(in: &cancellables)
    }
}
