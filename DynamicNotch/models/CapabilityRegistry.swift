//
//  CapabilityRegistry.swift
//  DynamicNotch
//
//  Single source of truth for every trigger and action the extensions system
//  supports. Add a new capability by adding one case to `TriggerID`/`ActionID`
//  and one descriptor below — everything else (the human-readable reference
//  list, the on-device generation schema, JSON validation, and the picker
//  rule builder's controls) is meant to be generated from this file, so it
//  can never drift out of sync with what `ExtensionEventBus` actually fires
//  or `ExtensionActionExecutor` actually performs.
//
//  `implementedBy` on each descriptor names the exact function that does the
//  work, so "what backs this capability" is always a grep away instead of
//  living only in a switch statement.
//

import Foundation

// MARK: - Identifiers

/// Every event an extension can react to. Raw value is the wire identifier
/// used in a rule's `trigger` field once extensions are persisted as JSON.
enum TriggerID: String, CaseIterable, Codable, Sendable {
    case batteryLevelChanged = "battery.levelChanged"
    case batteryChargingChanged = "battery.chargingChanged"
    case batteryLowPowerModeChanged = "battery.lowPowerModeChanged"
    case volumeChanged = "volume.changed"
    case brightnessChanged = "brightness.changed"
    case mediaPlaybackChanged = "media.playbackChanged"
    case mediaTrackChanged = "media.trackChanged"
    case calendarInMeetingChanged = "calendar.inMeetingChanged"
    case calendarEventStartingSoon = "calendar.eventStartingSoon"
    case thermalStateChanged = "thermal.stateChanged"
    case audioDeviceChanged = "audioDevice.changed"
    case bluetoothDeviceBatteryChanged = "bluetoothDevice.batteryChanged"
    case clipboardChanged = "clipboard.changed"
    case downloadStarted = "download.started"
    case downloadCompleted = "download.completed"
    case aiUsageThresholdCrossed = "aiUsage.thresholdCrossed"
    case aiUsageWindowReset = "aiUsage.windowReset"
    case caffeineStateChanged = "caffeine.stateChanged"
    case sleepWillSleep = "sleep.willSleep"
    case sleepDidWake = "sleep.didWake"
    case appFrontmostChanged = "app.frontmostChanged"
    case appLaunched = "app.launched"
    case appTerminated = "app.terminated"
    case timeTick = "time.tick"
    case displayConnected = "display.connected"
    case displayDisconnected = "display.disconnected"
    case webcamActiveChanged = "webcam.activeChanged"
    case airplayConnectingChanged = "airplay.connectingChanged"
    case durationElapsed = "extension.durationElapsed"
}

/// Every action an extension can ask the app to perform. Raw value is the
/// wire identifier used in an action step's `action` field.
enum ActionID: String, CaseIterable, Codable, Sendable {
    case notificationRequest = "notification.request"
    case notificationShowInApp = "notification.showInApp"
    case caffeineSet = "caffeine.set"
    case audioOutputSet = "audioOutput.set"
    case sneakPeekShow = "sneakPeek.show"
    case volumeSet = "volume.set"
    case brightnessSet = "brightness.set"
    case appOpen = "app.open"
    case appQuit = "app.quit"
    case clipboardSetText = "clipboard.setText"
    case webcamSet = "webcam.set"
    case mediaPlayPause = "media.playPause"
    case mediaNextTrack = "media.nextTrack"
    case mediaPreviousTrack = "media.previousTrack"
    case shortcutRun = "shortcut.run"
    case aiUsageProviderSet = "aiUsageProvider.set"
    case hudReplacementSet = "hudReplacement.set"
    case notchSetTab = "notch.setTab"
    case fanFloorSet = "fan.floorSet"
}

// MARK: - Structured payload schema

/// One field inside a trigger's or action's payload, typed for the picker
/// rule builder — separate from `payloadFields: [String]` below (which stays
/// free text for `referenceText()`/`chatbotPrompt()`/on-device generation)
/// so nothing about the AI-facing docs changes here.
struct PayloadFieldDescriptor: Sendable {
    let key: String
    let label: String
    let type: PayloadFieldType
    let isRequired: Bool
    /// Slider granularity for `.doubleRange`/`.intRange` fields — `nil` means
    /// continuous. Only set where snapping actually matters (fan speed);
    /// most range fields stay continuous.
    let step: Double?
    /// For `.bool` fields only: what an absent key means to this action's own
    /// `performXxx`/`currentlyMatches` pair — must mirror their `?? default`
    /// fallback exactly. Defaults to `true` (every bool field but `appQuit`'s
    /// `running` follows that convention). Lets `scaffoldPrerequisite` negate
    /// a field generically instead of hardcoding a per-action exception.
    let boolDefault: Bool

    init(key: String, label: String, type: PayloadFieldType, isRequired: Bool = true, step: Double? = nil, boolDefault: Bool = true) {
        self.key = key
        self.step = step
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.boolDefault = boolDefault
    }
}

enum PayloadFieldType: Sendable {
    case bool
    case string
    case enumString(options: [String])
    case intRange(ClosedRange<Int>)
    case doubleRange(ClosedRange<Double>)
    /// A number with no natural bound (e.g. `epochSeconds`, `minutesUntilStart`) —
    /// still typed, so the picker offers a numeric field instead of a slider
    /// with an arbitrary range that isn't actually documented anywhere.
    case freeInt
    case freeDouble

    /// Which `MatchCondition.Operator`s make sense against a field of this
    /// type — drives the condition builder's operator picker so it never
    /// offers, say, `contains` against a boolean.
    var applicableOperators: [MatchCondition.Operator] {
        switch self {
        case .bool:
            return [.equals, .notEquals]
        case .string, .enumString:
            return [.equals, .notEquals, .contains]
        case .intRange, .doubleRange, .freeInt, .freeDouble:
            return [.equals, .notEquals, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual]
        }
    }

    /// A sensible starting value when a new condition/payload field is
    /// scaffolded — the low end of a range, empty string, or `false`.
    var defaultValue: ExtensionValue {
        switch self {
        case .bool: return .bool(false)
        case .string, .enumString: return .string("")
        case .intRange(let range): return .int(range.lowerBound)
        case .doubleRange(let range): return .double(range.lowerBound)
        case .freeInt: return .int(0)
        case .freeDouble: return .double(0)
        }
    }
}

// MARK: - Descriptors

struct TriggerDescriptor: Sendable {
    let id: TriggerID
    let label: String
    let summary: String
    /// Human-readable payload field docs, e.g. "level: Int (0-100)".
    let payloadFields: [String]
    /// Typed mirror of `payloadFields`, for the picker rule builder's
    /// condition editor. See `PayloadFieldDescriptor`.
    let payloadSchema: [PayloadFieldDescriptor]
    /// Where the event is actually detected and emitted.
    let implementedBy: String
}

struct ActionDescriptor: Sendable {
    enum Tier: String, Sendable {
        /// Writes an existing app setting/state — no user-visible interruption.
        case settingsWrite
        /// Does something visible/audible, or touches hardware.
        case realAction
    }

    let id: ActionID
    let label: String
    let summary: String
    let tier: Tier
    let payloadFields: [String]
    /// Typed mirror of `payloadFields`, for the picker rule builder's
    /// action-step editor. See `PayloadFieldDescriptor`.
    let payloadSchema: [PayloadFieldDescriptor]
    /// The exact function that performs this action.
    let implementedBy: String
    /// Whether this action's live state can be read back and compared,
    /// making it legal to reference inside a rule's `prerequisites` (see
    /// `ExtensionActionStep`, `PrerequisiteMode`). False for pure
    /// fire-and-forget commands that have nothing persistent to check —
    /// e.g. posting a notification or skipping a track. Backed by a
    /// `currentlyMatches`-style function in `ExtensionActionExecutor`
    /// alongside the `performXxx` named in `implementedBy`.
    let prerequisiteEligible: Bool
    /// True only for actions that leave persistent state active with no
    /// automatic self-clearing mechanism — currently just `fanFloorSet`
    /// (`SettingsView` already carries a standing "Fan floor active …
    /// Disable" banner purely because nothing else stops a floor from being
    /// left on forever). When true, `CapabilityRegistry.issues(in:)` requires
    /// some other rule in the same extension with a `.exit`-mode gate on this
    /// action before the extension can be saved — a stronger requirement
    /// than the ordinary `prerequisiteEligible` nudge every other eligible
    /// action gets.
    let requiresPairedExitRule: Bool

    init(
        id: ActionID, label: String, summary: String, tier: Tier,
        payloadFields: [String], payloadSchema: [PayloadFieldDescriptor], implementedBy: String,
        prerequisiteEligible: Bool, requiresPairedExitRule: Bool = false
    ) {
        self.id = id
        self.label = label
        self.summary = summary
        self.tier = tier
        self.payloadFields = payloadFields
        self.payloadSchema = payloadSchema
        self.implementedBy = implementedBy
        self.prerequisiteEligible = prerequisiteEligible
        self.requiresPairedExitRule = requiresPairedExitRule
    }

    /// The action's one and only payload field, when its whole payload is
    /// exactly one `Bool` (e.g. `caffeineSet`, `webcamSet`) — lets the
    /// picker rule builder show a single inline On/Off control next to the
    /// action picker instead of a separate "Enabled" checkbox below it,
    /// since for these the checkbox and the picker are really one idea
    /// ("Turn Caffeine on/off" + a redundant toggle read as two things).
    /// `nil` for actions with more than one field (e.g. `fanFloorSet`'s
    /// `enabled` + `level`), where the extra fields still need their own row.
    var singleBoolField: PayloadFieldDescriptor? {
        guard payloadSchema.count == 1, case .bool = payloadSchema[0].type else { return nil }
        return payloadSchema[0]
    }
}

// MARK: - Registry

enum CapabilityRegistry {
    /// Plain-language authoring tips, without the leading "- " — kept as
    /// structured data (instead of only living inside `referenceText()`)
    /// so the in-app reference viewer can render them as its own list
    /// instead of parsing them back out of a generated string.
    static let tips: [String] = [
        "To match which app is frontmost/launched/quit, use condition field \"name\" with op \"contains\" and the app's plain display name (e.g. \"Xcode\", \"Safari\") \u{2014} not \"bundleIdentifier\". Exact bundle identifiers are easy to get wrong from memory; the display name is not.",
        "A rule can run several actions: \"actions\" is an array, run in order, once the trigger matches and prerequisites (if any) pass.",
        "\"prerequisites\" is a COMPULSORY ambient-state gate, checked AFTER the trigger/conditions match and BEFORE actions run \u{2014} required whenever any action inside \"actions\" is marked (usable as a prerequisite) below, since that's exactly what stops a state-setting action from re-firing every time its trigger recurs. Only omit \"prerequisites\" when every action in the rule is NOT marked (usable as a prerequisite) \u{2014} a pure fire-and-forget command with nothing to gate on. Each entry has the exact same shape as an action step (\"action\" + \"payload\"), but is read as current live state instead of performed.",
        "\"mode\" controls how \"prerequisites\" are evaluated: \"entry\" (default) runs the rule if ANY prerequisite's live state currently matches its payload, skipping only if ALL currently mismatch. \"exit\" runs the rule if ANY prerequisite's live state currently MISmatches its payload, skipping only if ALL currently match. Pair an \"entry\" rule and an \"exit\" rule that reuse the exact same prerequisites and payload values, but each with their own independent trigger, to build an on/off pair \u{2014} e.g. entry trigger \"app.frontmostChanged\"/Xcode with prerequisites [caffeine.set: {enabled:false}] mode entry, and a separate exit rule with trigger \"app.frontmostChanged\"/Safari, the SAME prerequisites, mode \"exit\".",
        "\"sustainFor\" (optional, seconds) puts a resettable timer on a rule: every time this rule's trigger/conditions match, its \"actions\" run as normal AND this timer (re)starts. If the timer ever completes without being reset first, it fires the \"extension.durationElapsed\" trigger, with a payload identical to the fields of whatever trigger set the timer. For a handful of triggers with an obvious \"current value\" (app.frontmostChanged, volume.changed, brightness.changed, media.playbackChanged, caffeine.stateChanged, webcam.activeChanged, audioDevice.changed, thermal.stateChanged) the timer ALSO keeps resetting on its own every few seconds for as long as that live value keeps satisfying the same conditions \u{2014} so it measures continuous real time in that state, not just \"how long since the last matching event.\" Other triggers can only reset it via an actual recurring event. Use this for \"undo after N straight minutes of this\" \u{2014} e.g. trigger \"app.frontmostChanged\" with condition name contains \"Xcode\", actions [caffeine.set: {enabled:true}], sustainFor 7200 (2 hours); then a separate rule with trigger \"extension.durationElapsed\" and the SAME condition (name contains \"Xcode\") to turn Caffeine back off once Xcode has been away from the foreground \u{2014} whether quit, or just not reactivated \u{2014} for a full 2 hours. This is independent of the ordinary \"Xcode quit\" exit rule you'd also write for the immediate case.",
        "\"app.open\"/\"app.quit\" each read back \"is this app currently running\" through their own \"running\" field (app.open defaults it to true, app.quit defaults it to false), so each is its own correct prerequisite gate — NOT the other action. Gating \"app.open\" on \"only if not already running\" means a prerequisite of app.open with the SAME bundleIdentifier and \"running\":false; gating \"app.quit\" on \"only if currently running\" means a prerequisite of app.quit with \"running\":true.",
    ]

    static let triggers: [TriggerDescriptor] = [
        TriggerDescriptor(
            id: .batteryLevelChanged, label: "Battery level changed",
            summary: "Fires whenever the battery percentage changes.",
            payloadFields: ["level: Int (0-100)"],
            payloadSchema: [PayloadFieldDescriptor(key: "level", label: "Level", type: .intRange(0...100))],
            implementedBy: "ExtensionEventBus.observeBattery()"
        ),
        TriggerDescriptor(
            id: .batteryChargingChanged, label: "Charging state changed",
            summary: "Fires when the Mac starts or stops charging.",
            payloadFields: ["isCharging: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "isCharging", label: "Charging", type: .bool)],
            implementedBy: "ExtensionEventBus.observeBattery()"
        ),
        TriggerDescriptor(
            id: .batteryLowPowerModeChanged, label: "Low Power Mode changed",
            summary: "Fires when Low Power Mode is turned on or off.",
            payloadFields: ["enabled: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "enabled", label: "Enabled", type: .bool)],
            implementedBy: "ExtensionEventBus.observeBattery()"
        ),
        TriggerDescriptor(
            id: .volumeChanged, label: "Volume changed",
            summary: "Fires when the system output volume or mute state changes.",
            payloadFields: ["level: Double (0-1)", "muted: Bool"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "level", label: "Level", type: .doubleRange(0...1)),
                PayloadFieldDescriptor(key: "muted", label: "Muted", type: .bool),
            ],
            implementedBy: "ExtensionEventBus.observeVolume()"
        ),
        TriggerDescriptor(
            id: .brightnessChanged, label: "Brightness changed",
            summary: "Fires when the main display's brightness changes.",
            payloadFields: ["level: Double (0-1)"],
            payloadSchema: [PayloadFieldDescriptor(key: "level", label: "Level", type: .doubleRange(0...1))],
            implementedBy: "ExtensionEventBus.observeBrightness()"
        ),
        TriggerDescriptor(
            id: .mediaPlaybackChanged, label: "Playback started or paused",
            summary: "Fires when the active media source starts or pauses playback.",
            payloadFields: ["isPlaying: Bool", "title: String", "artist: String", "bundleIdentifier: String"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "isPlaying", label: "Playing", type: .bool),
                PayloadFieldDescriptor(key: "title", label: "Title", type: .string),
                PayloadFieldDescriptor(key: "artist", label: "Artist", type: .string),
                PayloadFieldDescriptor(key: "bundleIdentifier", label: "Bundle Identifier", type: .string),
            ],
            implementedBy: "ExtensionEventBus.observeMedia()"
        ),
        TriggerDescriptor(
            id: .mediaTrackChanged, label: "Track changed",
            summary: "Fires when the song title or artist changes.",
            payloadFields: ["title: String", "artist: String"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "title", label: "Title", type: .string),
                PayloadFieldDescriptor(key: "artist", label: "Artist", type: .string),
            ],
            implementedBy: "ExtensionEventBus.observeMedia()"
        ),
        TriggerDescriptor(
            id: .calendarInMeetingChanged, label: "In-meeting state changed",
            summary: "Fires when you enter or leave a calendar event with other participants.",
            payloadFields: ["inMeeting: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "inMeeting", label: "In Meeting", type: .bool)],
            implementedBy: "ExtensionEventBus.tickCalendar()"
        ),
        TriggerDescriptor(
            id: .calendarEventStartingSoon, label: "Event starting soon",
            summary: "Fires once, a few minutes before a calendar event starts.",
            payloadFields: ["title: String", "minutesUntilStart: Int"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "title", label: "Title", type: .string),
                PayloadFieldDescriptor(key: "minutesUntilStart", label: "Minutes Until Start", type: .freeInt),
            ],
            implementedBy: "ExtensionEventBus.tickCalendar()"
        ),
        TriggerDescriptor(
            id: .thermalStateChanged, label: "Thermal state changed",
            summary: "Fires when the system thermal pressure level changes.",
            payloadFields: ["state: String (nominal|fair|serious|critical)"],
            payloadSchema: [PayloadFieldDescriptor(key: "state", label: "State", type: .enumString(options: ["nominal", "fair", "serious", "critical"]))],
            implementedBy: "ExtensionEventBus.observeThermal()"
        ),
        TriggerDescriptor(
            id: .audioDeviceChanged, label: "Audio output device changed",
            summary: "Fires when the default output device changes (e.g. AirPods connected).",
            payloadFields: ["deviceName: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "deviceName", label: "Device Name", type: .string)],
            implementedBy: "ExtensionEventBus.observeAudioDevice()"
        ),
        TriggerDescriptor(
            id: .bluetoothDeviceBatteryChanged, label: "Bluetooth device battery changed",
            summary: "Fires when a connected Bluetooth audio device's battery level is read.",
            payloadFields: ["deviceName: String", "batteryLevel: Int (0-100, -1 if unknown)"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "deviceName", label: "Device Name", type: .string),
                PayloadFieldDescriptor(key: "batteryLevel", label: "Battery Level", type: .intRange(-1...100)),
            ],
            implementedBy: "ExtensionEventBus.observeBluetoothBattery()"
        ),
        TriggerDescriptor(
            id: .clipboardChanged, label: "Clipboard changed",
            summary: "Fires when new text is copied to the clipboard.",
            payloadFields: ["text: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "text", label: "Text", type: .string)],
            implementedBy: "ExtensionEventBus.pollClipboard()"
        ),
        TriggerDescriptor(
            id: .downloadStarted, label: "Download started",
            summary: "Fires when a new download appears in the Downloads folder.",
            payloadFields: ["fileName: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "fileName", label: "File Name", type: .string)],
            implementedBy: "ExtensionEventBus.observeDownloads()"
        ),
        TriggerDescriptor(
            id: .downloadCompleted, label: "Download completed",
            summary: "Fires when an in-progress download disappears (finished, cancelled, or failed).",
            payloadFields: [],
            payloadSchema: [],
            implementedBy: "ExtensionEventBus.observeDownloads()"
        ),
        TriggerDescriptor(
            id: .aiUsageThresholdCrossed, label: "AI usage threshold crossed",
            summary: "Fires when tracked Claude/ChatGPT usage crosses one of your configured alert points.",
            payloadFields: ["threshold: Int (1-100)", "provider: String"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "threshold", label: "Threshold", type: .intRange(1...100)),
                PayloadFieldDescriptor(key: "provider", label: "Provider", type: .string),
            ],
            implementedBy: "ExtensionEventBus.observeAIUsage()"
        ),
        TriggerDescriptor(
            id: .aiUsageWindowReset, label: "AI usage window reset",
            summary: "Fires when the tracked usage window rolls over.",
            payloadFields: ["previousPeak: Double (0-100)"],
            payloadSchema: [PayloadFieldDescriptor(key: "previousPeak", label: "Previous Peak", type: .doubleRange(0...100))],
            implementedBy: "ExtensionEventBus.observeAIUsage()"
        ),
        TriggerDescriptor(
            id: .caffeineStateChanged, label: "Caffeine state changed",
            summary: "Fires when Caffeine (sleep prevention) is turned on or off, by anything.",
            payloadFields: ["isActive: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "isActive", label: "Active", type: .bool)],
            implementedBy: "ExtensionEventBus.observeCaffeine()"
        ),
        TriggerDescriptor(
            id: .sleepWillSleep, label: "Mac going to sleep",
            summary: "Fires right before the Mac sleeps.",
            payloadFields: [],
            payloadSchema: [],
            implementedBy: "ExtensionEventBus.observeSleepWake()"
        ),
        TriggerDescriptor(
            id: .sleepDidWake, label: "Mac woke up",
            summary: "Fires right after the Mac wakes from sleep.",
            payloadFields: [],
            payloadSchema: [],
            implementedBy: "ExtensionEventBus.observeSleepWake()"
        ),
        TriggerDescriptor(
            id: .appFrontmostChanged, label: "Frontmost app changed",
            summary: "Fires when a different app becomes frontmost.",
            payloadFields: [
                "name: String (display name, e.g. \"Xcode\" — match on this, see TIPS)",
                "bundleIdentifier: String",
            ],
            payloadSchema: [
                PayloadFieldDescriptor(key: "name", label: "Name", type: .string),
                PayloadFieldDescriptor(key: "bundleIdentifier", label: "Bundle Identifier", type: .string),
            ],
            implementedBy: "ExtensionEventBus.observeAppLifecycle()"
        ),
        TriggerDescriptor(
            id: .appLaunched, label: "App launched",
            summary: "Fires when any app finishes launching.",
            payloadFields: [
                "name: String (display name, e.g. \"Xcode\" — match on this, see TIPS)",
                "bundleIdentifier: String",
            ],
            payloadSchema: [
                PayloadFieldDescriptor(key: "name", label: "Name", type: .string),
                PayloadFieldDescriptor(key: "bundleIdentifier", label: "Bundle Identifier", type: .string),
            ],
            implementedBy: "ExtensionEventBus.observeAppLifecycle()"
        ),
        TriggerDescriptor(
            id: .appTerminated, label: "App quit",
            summary: "Fires when any app terminates.",
            payloadFields: [
                "name: String (display name, e.g. \"Xcode\" — match on this, see TIPS)",
                "bundleIdentifier: String",
            ],
            payloadSchema: [
                PayloadFieldDescriptor(key: "name", label: "Name", type: .string),
                PayloadFieldDescriptor(key: "bundleIdentifier", label: "Bundle Identifier", type: .string),
            ],
            implementedBy: "ExtensionEventBus.observeAppLifecycle()"
        ),
        TriggerDescriptor(
            id: .timeTick, label: "Time tick",
            summary: "Fires once a minute. The base signal interval/at-time rules are built on.",
            payloadFields: ["epochSeconds: Int"],
            payloadSchema: [PayloadFieldDescriptor(key: "epochSeconds", label: "Epoch Seconds", type: .freeInt)],
            implementedBy: "ExtensionEventBus.observeTimeTick()"
        ),
        TriggerDescriptor(
            id: .displayConnected, label: "Display connected",
            summary: "Fires when an external display is connected.",
            payloadFields: ["displayUUID: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "displayUUID", label: "Display UUID", type: .string)],
            implementedBy: "ExtensionEventBus.tickDisplays()"
        ),
        TriggerDescriptor(
            id: .displayDisconnected, label: "Display disconnected",
            summary: "Fires when an external display is disconnected.",
            payloadFields: ["displayUUID: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "displayUUID", label: "Display UUID", type: .string)],
            implementedBy: "ExtensionEventBus.tickDisplays()"
        ),
        TriggerDescriptor(
            id: .webcamActiveChanged, label: "Webcam active state changed",
            summary: "Fires when the camera preview session starts or stops running.",
            payloadFields: ["isActive: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "isActive", label: "Active", type: .bool)],
            implementedBy: "ExtensionEventBus.observeWebcam()"
        ),
        TriggerDescriptor(
            id: .airplayConnectingChanged, label: "AirPlay device connecting",
            summary: "Fires while a dormant AirPlay device is being woken and connected.",
            payloadFields: ["connectingCount: Int"],
            payloadSchema: [PayloadFieldDescriptor(key: "connectingCount", label: "Connecting Count", type: .freeInt)],
            implementedBy: "ExtensionEventBus.observeAirPlay()"
        ),
        TriggerDescriptor(
            id: .durationElapsed, label: "Sustained condition timed out",
            summary: "Fires when a rule with \"sustainFor\" set doesn't re-match its own trigger/conditions before that many seconds pass — see TIPS. Payload mirrors whatever fields the timed-out rule's own trigger has.",
            payloadFields: [],
            payloadSchema: [],
            implementedBy: "ExtensionsManager.armSustainTimer(ruleID:seconds:payload:)"
        ),
    ]

    static let actions: [ActionDescriptor] = [
        ActionDescriptor(
            id: .notificationRequest, label: "Show a notification",
            summary: "Posts a system notification.",
            tier: .realAction,
            payloadFields: ["title: String", "body: String"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "title", label: "Title", type: .string),
                PayloadFieldDescriptor(key: "body", label: "Body", type: .string, isRequired: false),
            ],
            implementedBy: "ExtensionActionExecutor.performNotificationRequest(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .notificationShowInApp, label: "Show an in-app alert",
            summary: "Shows a brief banner inside the closed notch instead of a system notification \u{2014} no notification permission needed, only visible while the notch is closed.",
            tier: .realAction,
            payloadFields: ["title: String", "message: String (optional)", "icon: String (optional, SF Symbol name, defaults to bolt.badge.a)"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "title", label: "Title", type: .string),
                PayloadFieldDescriptor(key: "message", label: "Message", type: .string, isRequired: false),
                PayloadFieldDescriptor(key: "icon", label: "Icon (SF Symbol)", type: .string, isRequired: false),
            ],
            implementedBy: "ExtensionActionExecutor.performInAppAlertShow(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .caffeineSet, label: "Turn Caffeine on/off",
            summary: "Enables or disables sleep prevention. Safe to fire repeatedly \u{2014} does nothing if Caffeine is already in the requested state.",
            tier: .realAction,
            payloadFields: ["enabled: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "enabled", label: "Enabled", type: .bool, isRequired: false)],
            implementedBy: "ExtensionActionExecutor.performCaffeineSet(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .audioOutputSet, label: "Switch audio output",
            summary: "Switches the default output device by name (wakes a dormant AirPlay device if needed).",
            tier: .realAction,
            payloadFields: ["deviceName: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "deviceName", label: "Device Name", type: .string)],
            implementedBy: "ExtensionActionExecutor.performAudioOutputSet(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .sneakPeekShow, label: "Flash the in-notch HUD",
            summary: "Briefly shows the closed-notch HUD for a given type/value.",
            tier: .realAction,
            payloadFields: ["type: String (volume|brightness|backlight|music|download|battery)", "value: Double (0-1)"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "type", label: "Type", type: .enumString(options: ["volume", "brightness", "backlight", "music", "download", "battery"]), isRequired: false),
                PayloadFieldDescriptor(key: "value", label: "Value", type: .doubleRange(0...1), isRequired: false),
            ],
            implementedBy: "ExtensionActionExecutor.performSneakPeekShow(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .volumeSet, label: "Set volume",
            summary: "Sets the system output volume.",
            tier: .realAction,
            payloadFields: ["level: Double (0-1)"],
            payloadSchema: [PayloadFieldDescriptor(key: "level", label: "Level", type: .doubleRange(0...1))],
            implementedBy: "ExtensionActionExecutor.performVolumeSet(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .brightnessSet, label: "Set brightness",
            summary: "Sets the main display's brightness.",
            tier: .realAction,
            payloadFields: ["level: Double (0-1)"],
            payloadSchema: [PayloadFieldDescriptor(key: "level", label: "Level", type: .doubleRange(0...1))],
            implementedBy: "ExtensionActionExecutor.performBrightnessSet(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .appOpen, label: "Open an app",
            summary: "Launches or activates an app by bundle identifier. \"running\" (default true) is what a prerequisite gate reads back — leave it out when just performing the action.",
            tier: .realAction,
            payloadFields: ["bundleIdentifier: String", "running: Bool (default true)"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "bundleIdentifier", label: "Bundle Identifier", type: .string),
                PayloadFieldDescriptor(key: "running", label: "Running", type: .bool, isRequired: false),
            ],
            implementedBy: "ExtensionActionExecutor.performAppOpen(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .appQuit, label: "Quit an app",
            summary: "Terminates a running app by bundle identifier. \"running\" (default false) is what a prerequisite gate reads back — leave it out when just performing the action.",
            tier: .realAction,
            payloadFields: ["bundleIdentifier: String", "running: Bool (default false)"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "bundleIdentifier", label: "Bundle Identifier", type: .string),
                PayloadFieldDescriptor(key: "running", label: "Running", type: .bool, isRequired: false, boolDefault: false),
            ],
            implementedBy: "ExtensionActionExecutor.performAppQuit(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .clipboardSetText, label: "Set clipboard text",
            summary: "Replaces the clipboard contents with the given text.",
            tier: .realAction,
            payloadFields: ["text: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "text", label: "Text", type: .string)],
            implementedBy: "ExtensionActionExecutor.performClipboardSetText(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .webcamSet, label: "Turn webcam preview on/off",
            summary: "Starts or stops the camera preview session.",
            tier: .realAction,
            payloadFields: ["enabled: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "enabled", label: "Enabled", type: .bool, isRequired: false)],
            implementedBy: "ExtensionActionExecutor.performWebcamSet(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .mediaPlayPause, label: "Play or pause media",
            summary: "Explicitly plays or pauses the active media source (not a toggle). No-ops if there's no active media session at all.",
            tier: .realAction,
            payloadFields: ["playing: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "playing", label: "Playing", type: .bool, isRequired: false)],
            implementedBy: "ExtensionActionExecutor.performMediaPlayPause(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .mediaNextTrack, label: "Next track",
            summary: "Skips to the next track. No-ops if there's no active media session.",
            tier: .realAction,
            payloadFields: [],
            payloadSchema: [],
            implementedBy: "ExtensionActionExecutor.performMediaNextTrack(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .mediaPreviousTrack, label: "Previous track",
            summary: "Skips to the previous track. No-ops if there's no active media session.",
            tier: .realAction,
            payloadFields: [],
            payloadSchema: [],
            implementedBy: "ExtensionActionExecutor.performMediaPreviousTrack(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .shortcutRun, label: "Run a Shortcut",
            summary: "Runs a macOS Shortcut by name.",
            tier: .realAction,
            payloadFields: ["name: String"],
            payloadSchema: [PayloadFieldDescriptor(key: "name", label: "Name", type: .string)],
            implementedBy: "ExtensionActionExecutor.performShortcutRun(_:)",
            prerequisiteEligible: false
        ),
        ActionDescriptor(
            id: .aiUsageProviderSet, label: "Switch tracked AI provider",
            summary: "Switches which AI usage provider (Claude or ChatGPT) is tracked and shown.",
            tier: .settingsWrite,
            payloadFields: ["provider: String (claude|chatgpt)"],
            payloadSchema: [PayloadFieldDescriptor(key: "provider", label: "Provider", type: .enumString(options: ["claude", "chatgpt"]))],
            implementedBy: "ExtensionActionExecutor.performAIUsageProviderSet(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .hudReplacementSet, label: "Turn HUD replacement on/off",
            summary: "Enables or disables replacing the system volume/brightness HUD.",
            tier: .settingsWrite,
            payloadFields: ["enabled: Bool"],
            payloadSchema: [PayloadFieldDescriptor(key: "enabled", label: "Enabled", type: .bool, isRequired: false)],
            implementedBy: "ExtensionActionExecutor.performHUDReplacementSet(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .notchSetTab, label: "Switch notch tab",
            summary: "Switches the open notch to the Home or Shelf tab.",
            tier: .settingsWrite,
            payloadFields: ["view: String (home|shelf)"],
            payloadSchema: [PayloadFieldDescriptor(key: "view", label: "View", type: .enumString(options: ["home", "shelf"]))],
            implementedBy: "ExtensionActionExecutor.performNotchSetTab(_:)",
            prerequisiteEligible: true
        ),
        ActionDescriptor(
            id: .fanFloorSet, label: "Set fan speed floor",
            summary: "Sets a minimum fan speed the thermal curve can't go below — the thermal curve (or macOS itself) can still push fans higher if needed, but never lower than this floor. \"level\" is required when enabled is true.",
            tier: .realAction,
            payloadFields: ["enabled: Bool", "level: Double (0-1, required when enabled)"],
            payloadSchema: [
                PayloadFieldDescriptor(key: "enabled", label: "Enabled", type: .bool, isRequired: false),
                PayloadFieldDescriptor(key: "level", label: "Level", type: .doubleRange(0...1), step: 0.05),
            ],
            implementedBy: "ExtensionActionExecutor.performFanFloorSet(_:)",
            prerequisiteEligible: true,
            requiresPairedExitRule: true
        ),
    ]

    static func trigger(_ id: TriggerID) -> TriggerDescriptor {
        // Force-unwrap is safe: every TriggerID case has exactly one descriptor above,
        // and CapabilityRegistryTests (if added) should assert that invariant.
        triggers.first { $0.id == id }!
    }

    static func action(_ id: ActionID) -> ActionDescriptor {
        actions.first { $0.id == id }!
    }

    // MARK: - Safety validation

    /// Human-readable problems with an otherwise-decodable rule set — closes
    /// three gaps between what TIPS already documents and what was actually
    /// enforced in code before this:
    ///
    /// 1. Any `prerequisiteEligible` action referenced in a rule's `actions`
    ///    must also appear in that same rule's `prerequisites` — makes the
    ///    "COMPULSORY" TIPS language actually true, instead of only advisory.
    /// 2. Any action marked `requiresPairedExitRule` (currently only
    ///    `fanFloorSet`) used with `enabled: true` must have some *other*
    ///    rule in the same record with `mode == .exit` gated on it.
    /// 3. In an `entry`-mode rule specifically, a prerequisite step's `.bool`
    ///    field(s) can't equal its matching action step's own field — that's
    ///    the opposite of what "entry" means (see TIPS): the gate should
    ///    read the state the action *isn't* in yet, not the one it's headed
    ///    to. (This check only applies to `entry` mode — `exit`-mode rules
    ///    built by `makingExitCounterpart()` deliberately set the action's
    ///    payload to match its own prerequisite, so equality there is the
    ///    correct, intended shape.)
    ///
    /// Empty result means the rule set is safe to save. Called from
    /// `ExtensionEditorView` for both the JSON-typed and picker-built paths,
    /// since both funnel through the same `[ExtensionRule]`.
    static func issues(in rules: [ExtensionRule]) -> [String] {
        var issues: [String] = []

        for (index, rule) in rules.enumerated() {
            for actionID in rule.actionsMissingPrerequisiteGate {
                issues.append("Rule \(index + 1): \"\(actionID.rawValue)\" needs a prerequisite gate.")
            }
        }

        for actionID in actionsRequiringExitRule(in: rules) {
            issues.append("\"\(actionID.rawValue)\" is turned on but no rule turns it back off.")
        }

        for (index, rule) in rules.enumerated() {
            for actionID in rule.actionsWithRedundantPrerequisite {
                issues.append("Rule \(index + 1): \"\(actionID.rawValue)\"'s prerequisite matches its own action's state \u{2014} it will never run except when it would already be a no-op.")
            }
        }

        return issues
    }

    /// The subset of `requiresPairedExitRule` actions that are turned on
    /// somewhere in `rules` with no other rule's `.exit`-mode gate actually
    /// turning them back off. Exposed separately from `issues(in:)` so the
    /// rule builder UI can render its record-level banner directly from this
    /// instead of parsing `issues(in:)`'s generated text back apart.
    ///
    /// Requires more than an `.exit`-mode rule merely *referencing* the
    /// action in `prerequisites` — a rule can satisfy that structurally
    /// while still being wired backwards (see `scaffoldExitRule`'s original
    /// bug, where the gate polarity was inverted and the "exit" rule only
    /// ever fired while the action was already off). Also requiring one of
    /// its `actions` to actually set the action to its off state closes that
    /// gap: a rule can no longer satisfy this check without actually
    /// relinquishing control.
    static func actionsRequiringExitRule(in rules: [ExtensionRule]) -> [ActionID] {
        ActionID.allCases.filter { actionID in
            guard action(actionID).requiresPairedExitRule else { return false }
            let turnsOn = rules.contains { rule in
                rule.actions.contains { $0.action == actionID && ($0.payload["enabled"]?.boolValue ?? true) }
            }
            guard turnsOn else { return false }
            let hasExit = rules.contains { rule in
                rule.mode == .exit
                    && rule.prerequisites.contains { $0.action == actionID }
                    && rule.actions.contains { $0.action == actionID && !($0.payload["enabled"]?.boolValue ?? true) }
            }
            return !hasExit
        }
    }

    // MARK: - Human-readable reference

    /// The full trigger/action list as plain text — generated from the same
    /// descriptors that back the schema and validation, so this can never say
    /// anything the app doesn't actually support. Used both by the in-app
    /// "See Reference" viewer and as the core of `chatbotPrompt(currentRulesJSON:)`.
    static func referenceText() -> String {
        var lines: [String] = []

        lines.append("TIPS")
        for tip in tips {
            lines.append("- \(tip)")
        }
        lines.append("")

        lines.append("TRIGGERS (what an extension can react to)")
        for descriptor in triggers {
            lines.append("- \(descriptor.id.rawValue): \(descriptor.summary)")
            if !descriptor.payloadFields.isEmpty {
                lines.append("    payload fields: " + descriptor.payloadFields.joined(separator: ", "))
            }
        }

        lines.append("")
        lines.append("ACTIONS (what an extension can ask the app to do)")
        for descriptor in actions {
            let eligibility = descriptor.prerequisiteEligible ? " (usable as a prerequisite)" : ""
            lines.append("- \(descriptor.id.rawValue): \(descriptor.summary)\(eligibility)")
            if !descriptor.payloadFields.isEmpty {
                lines.append("    payload fields: " + descriptor.payloadFields.joined(separator: ", "))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// A ready-to-paste prompt for an external chatbot: the rule shape, the
    /// full reference list, and the extension's current JSON so an edit
    /// round-trips instead of starting over. The person pastes the response
    /// back into the same JSON editor, which validates it the same way
    /// on-device or hand-typed JSON would be.
    static func chatbotPrompt(currentRulesJSON: String, request: String = "<describe what you want here>") -> String {
        """
        I'm configuring an automation ("extension") for a Mac app called DynamicNotch. \
        An extension is a JSON array of rules with this shape:

        {
          "trigger": "<a trigger id from the list below>",
          "conditions": [
            { "field": "<a payload field for that trigger>", "op": "equals | notEquals | greaterThan | greaterThanOrEqual | lessThan | lessThanOrEqual | contains", "value": <string, number, or bool> }
          ],
          "prerequisites": [
            { "action": "<an action id marked (usable as a prerequisite) below>", "payload": { "...": "the payload fields that action expects" } }
          ],
          "mode": "entry | exit",
          "sustainFor": <number of seconds, optional>,
          "actions": [
            { "action": "<an action id from the list below>", "payload": { "...": "the payload fields that action expects" } }
          ]
        }

        `conditions` is optional — omit it (or leave it empty) to match every occurrence of the trigger, ANDed together. \
        `prerequisites` is a COMPULSORY ambient-state gate checked after the trigger/conditions match and before \
        `actions` run \u{2014} REQUIRED whenever any action inside `actions` is marked "(usable as a prerequisite)" in \
        the ACTIONS list below, because that's exactly what stops a state-setting action from re-firing every time its \
        trigger recurs. Only omit `prerequisites` when every action in the rule is a pure fire-and-forget command (not \
        marked "(usable as a prerequisite)"). Each entry has the exact same shape as an action step, but is read as \
        current live state instead of performed. `mode` (default "entry") sets how `prerequisites` are evaluated: \
        "entry" runs the rule if ANY prerequisite's live state currently matches its payload, skipping only if ALL \
        currently mismatch; "exit" runs the rule if ANY prerequisite's live state currently MISmatches its payload, \
        skipping only if ALL currently match. To build an on/off pair, write two separate rules with their own \
        independent triggers that reuse the exact same `prerequisites` list \u{2014} one with mode "entry", one with \
        mode "exit" \u{2014} rather than trying to express both directions in one rule. `actions` is a non-empty array \
        run in order once the rule's gate passes. `sustainFor` (optional, seconds) is a separate, independent \
        mechanism: it puts a resettable timer on THIS rule that (re)starts every time this rule's trigger/conditions \
        match, and fires the "extension.durationElapsed" trigger (payload identical to this rule's own trigger's \
        fields) if that timer ever completes without the rule matching again first. Use it for "undo automatically \
        if this stays true for N without ever going away and coming back" — write a second rule with trigger \
        "extension.durationElapsed" and the same conditions to react to the timeout.

        Only use trigger and action ids from this exact list — never invent one:

        \(referenceText())

        What I want: \(request)

        Return ONLY the JSON array of rules, no commentary, no markdown code fence.

        Current rules (edit these, or replace the array entirely):
        \(currentRulesJSON)
        """
    }
}
