import Testing
@testable import DynamicNotch

// MARK: - Tests
//
// Only failure paths that return before touching any manager, Defaults key, or system
// service are covered here — this suite runs inside the real app (TEST_HOST), so anything
// that reaches a live singleton would affect Mark's actual Caffeine/volume/clipboard/etc.
// state. Each case below was re-checked against the source to confirm the guard really is
// the first thing that runs.

@MainActor
@Suite("ExtensionActionExecutor failure paths that never touch live state")
struct ExtensionActionExecutorTests {

    @Test("Missing payload fields fail before any manager is touched")
    func missingPayloadFieldsFail() {
        #expect(ExtensionActionExecutor.performVolumeSet([:]) == .failed("Missing \"level\" in payload."))
        #expect(ExtensionActionExecutor.performBrightnessSet([:]) == .failed("Missing \"level\" in payload."))
        #expect(ExtensionActionExecutor.performAppQuit([:]) == .failed("Missing \"bundleIdentifier\" in payload."))
        #expect(ExtensionActionExecutor.performClipboardSetText([:]) == .failed("Missing \"text\" in payload."))
        #expect(ExtensionActionExecutor.performNotchSetTab([:]) == .failed("Missing \"view\" in payload."))
        #expect(ExtensionActionExecutor.performShortcutRun([:]) == .failed("Missing or invalid \"name\" in payload."))
        #expect(ExtensionActionExecutor.performAIUsageProviderSet([:]) == .failed("Missing \"provider\" in payload."))
    }

    @Test("An empty payload for the fan floor action defaults \"enabled\" to true, then fails on the missing level before writing any Defaults key")
    func fanFloorSetMissingLevelFails() {
        #expect(ExtensionActionExecutor.performFanFloorSet([:]) == .failed("Missing \"level\" in payload."))
    }

    @Test("An unrecognized AI usage provider fails without writing Defaults")
    func unknownAIUsageProviderFails() {
        let result = ExtensionActionExecutor.performAIUsageProviderSet(["provider": .string("not-a-provider")])
        #expect(result == .failed("Unknown provider \"not-a-provider\". Expected \"claude\" or \"chatgpt\"."))
    }

    @Test("An unrecognized notch view fails without touching NotchViewCoordinator")
    func unknownNotchViewFails() {
        let result = ExtensionActionExecutor.performNotchSetTab(["view": .string("sidebar")])
        #expect(result == .failed("Unknown view \"sidebar\". Expected \"home\" or \"shelf\"."))
    }

    @Test("An unknown bundle identifier fails performAppOpen without launching anything")
    func unknownBundleIdentifierFailsAppOpen() {
        let result = ExtensionActionExecutor.performAppOpen(["bundleIdentifier": .string("com.dynamicnotch.tests.does-not-exist")])
        #expect(result == .failed("Could not find an app with that bundle identifier."))
    }

    @Test("currentlyMatches always returns false for actions with no comparable live state")
    func nonEligibleActionsNeverMatch() {
        let nonEligible: [ActionID] = [
            .notificationRequest, .notificationShowInApp, .sneakPeekShow,
            .mediaNextTrack, .mediaPreviousTrack, .shortcutRun,
        ]
        for id in nonEligible {
            #expect(ExtensionActionExecutor.currentlyMatches(id, payload: [:]) == false, "\(id.rawValue) has no live state to compare against and must always report false")
        }
    }
}
