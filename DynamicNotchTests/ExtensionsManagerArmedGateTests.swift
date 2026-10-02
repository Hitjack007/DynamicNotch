import Testing
@testable import DynamicNotch

// MARK: - ArmedGateDecision
//
// ExtensionsManager.dispatch(_:event:record:) is a singleton MainActor method wired to a
// real event bus, real Defaults-backed persistence, and real ExtensionActionExecutor side
// effects — not something this suite can safely exercise end-to-end without touching Mark's
// actual app state (see ExtensionActionExecutorTests.swift's header for why). The arm/disarm
// decision itself is pulled out into the pure `armedGateDecision` function precisely so the
// sequencing can be verified here without any of that.

@Suite("ExtensionsManager.armedGateDecision")
struct ExtensionsManagerArmedGateTests {

    @Test("An entry-mode rule always runs and arms, regardless of prior armed state")
    func entryAlwaysRunsAndArms() {
        #expect(ExtensionsManager.armedGateDecision(mode: .entry, isCurrentlyArmed: false) == .run(armedAfter: true))
        #expect(ExtensionsManager.armedGateDecision(mode: .entry, isCurrentlyArmed: true) == .run(armedAfter: true))
    }

    @Test("An exit-mode rule only runs while armed, and disarms when it does")
    func exitRunsOnlyWhileArmedAndDisarms() {
        #expect(ExtensionsManager.armedGateDecision(mode: .exit, isCurrentlyArmed: true) == .run(armedAfter: false))
        #expect(ExtensionsManager.armedGateDecision(mode: .exit, isCurrentlyArmed: false) == .skip)
    }

    @Test("A full entry -> exit -> exit sequence: only the first exit after an entry fires")
    func fullArmDisarmSequence() {
        var armed = false

        // Entry fires: runs and arms.
        let first = ExtensionsManager.armedGateDecision(mode: .entry, isCurrentlyArmed: armed)
        guard case .run(let armedAfterEntry) = first else {
            Issue.record("Expected the entry rule to run")
            return
        }
        armed = armedAfterEntry
        #expect(armed)

        // First exit match: armed, so it runs and disarms.
        let second = ExtensionsManager.armedGateDecision(mode: .exit, isCurrentlyArmed: armed)
        guard case .run(let armedAfterFirstExit) = second else {
            Issue.record("Expected the first exit rule to run while armed")
            return
        }
        armed = armedAfterFirstExit
        #expect(!armed)

        // A second exit rule's trigger matching afterward (e.g. the sustainFor fallback,
        // once the immediate "app quit" exit already fired first) finds nothing armed and
        // is skipped — this is what lets several exit rules safely share one entry's gate.
        let third = ExtensionsManager.armedGateDecision(mode: .exit, isCurrentlyArmed: armed)
        #expect(third == .skip)
    }

    @Test("Re-arming after a disarm allows a later exit to run again")
    func rearmingAllowsExitAgain() {
        var armed = false
        if case .run(let after) = ExtensionsManager.armedGateDecision(mode: .entry, isCurrentlyArmed: armed) { armed = after }
        if case .run(let after) = ExtensionsManager.armedGateDecision(mode: .exit, isCurrentlyArmed: armed) { armed = after }
        #expect(!armed)

        // Entry fires again — re-arms, independent of the earlier cycle.
        if case .run(let after) = ExtensionsManager.armedGateDecision(mode: .entry, isCurrentlyArmed: armed) { armed = after }
        #expect(armed)

        #expect(ExtensionsManager.armedGateDecision(mode: .exit, isCurrentlyArmed: armed) == .run(armedAfter: false))
    }
}
