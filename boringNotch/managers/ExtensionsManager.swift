//
//  ExtensionsManager.swift
//  boringNotch
//
//  Owns the stored extension list and is the one place that turns a fired
//  ExtensionTriggerEvent into ExtensionActionExecutor calls. Deliberately no
//  priority system between extensions/rules — every enabled rule whose
//  trigger and conditions match just runs, independently.
//
//  Gating: once a rule's trigger+conditions match, its `prerequisites` (if
//  any) decide whether `actions` actually runs — see `PrerequisiteMode`.
//  There's no separate "was this rule previously matched" state to track
//  anymore: an "exit" rule is just another ordinary rule with its own
//  trigger, gated by the same prerequisites in the opposite polarity, so
//  every dispatch is a fresh, stateless check against live ambient state.
//

import Combine
import Foundation

@MainActor
final class ExtensionsManager: ObservableObject {
    static let shared = ExtensionsManager()

    @Published private(set) var extensions: [ExtensionRecord] = []

    private let store = ExtensionPersistenceService.shared
    private var eventCancellable: AnyCancellable?

    /// One in-flight countdown per rule with `sustainFor` set, keyed by `ExtensionRule.id`.
    /// In-memory only — timers don't survive a relaunch, they only arm once a matching
    /// event is actually observed while running. See `armSustainTimer`.
    private var sustainTimers: [UUID: Task<Void, Never>] = [:]

    private init() {
        extensions = store.load()
        eventCancellable = ExtensionEventBus.shared.eventPublisher
            .sink { [weak self] event in
                self?.handle(event)
            }
    }

    /// Explicit call site for the app delegate, matching the rest of the
    /// app's `.shared.bootstrap()`-style startup calls. Also re-reads from
    /// disk defensively in case anything touched the file before this ran.
    func activate() {
        extensions = store.load()
    }

    // MARK: - CRUD

    func add(_ record: ExtensionRecord) {
        extensions.append(record)
        persist()
    }

    func update(_ record: ExtensionRecord) {
        guard let index = extensions.firstIndex(where: { $0.id == record.id }) else { return }
        cancelSustainTimers(in: extensions[index])
        extensions[index] = record
        persist()
    }

    func remove(_ id: ExtensionRecord.ID) {
        if let record = extensions.first(where: { $0.id == id }) {
            cancelSustainTimers(in: record)
        }
        extensions.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ id: ExtensionRecord.ID, enabled: Bool) {
        guard let index = extensions.firstIndex(where: { $0.id == id }) else { return }
        if !enabled { cancelSustainTimers(in: extensions[index]) }
        extensions[index].enabled = enabled
        persist()
    }

    private func persist() {
        store.save(extensions)
    }

    // MARK: - Manual run (for a future "Try it now" button)
    // Not a simulation — there's no sandbox here, so this performs the real
    // actions immediately, exactly as if its trigger had fired. Deliberately
    // ignores `prerequisites`/`mode`: a manual run should always do
    // something, not silently no-op because the ambient gate didn't pass.

    @discardableResult
    func runNow(_ rule: ExtensionRule) async -> [ExtensionActionResult] {
        var results: [ExtensionActionResult] = []
        for step in rule.actions {
            results.append(await ExtensionActionExecutor.perform(step.action, payload: step.payload))
        }
        return results
    }

    // MARK: - Dispatch

    private func handle(_ event: ExtensionTriggerEvent) {
        for record in extensions where record.enabled {
            for rule in record.rules where rule.trigger == event.id {
                dispatch(rule, event: event)
            }
        }
    }

    private func dispatch(_ rule: ExtensionRule, event: ExtensionTriggerEvent) {
        guard rule.matches(event) else { return }

        // Independent of prerequisites/actions below — re-arms every time this rule's own
        // trigger/conditions match, regardless of whether its gate passes this time.
        if let sustainFor = rule.sustainFor {
            armSustainTimer(rule: rule, seconds: sustainFor, payload: event.payload)
        }

        guard prerequisitesPass(rule) else { return }
        for step in rule.actions {
            Task { await ExtensionActionExecutor.perform(step.action, payload: step.payload) }
        }
    }

    // MARK: - Sustain timers (see ExtensionRule.sustainFor)

    private func armSustainTimer(rule: ExtensionRule, seconds: TimeInterval, payload: [String: ExtensionValue]) {
        let ruleID = rule.id
        sustainTimers[ruleID]?.cancel()
        sustainTimers[ruleID] = Task { [weak self] in
            guard let self else { return }
            // Polls for a live "is this rule's condition still true right now" reading (see
            // ExtensionEventBus.currentPayload) so the countdown keeps resetting to the top
            // while it holds continuously — e.g. sitting on Xcode with no app switches at all
            // still counts as "still frontmost," not silence that lets the timer run out.
            // Triggers with no live equivalent just fall back to counting straight down, only
            // resettable by a genuine recurring event re-arming this Task from `dispatch`.
            let pollInterval = max(0.5, min(5, seconds / 3))
            var elapsedWithoutMatch: TimeInterval = 0
            var lastPayload = payload
            while elapsedWithoutMatch < seconds {
                let step = min(pollInterval, seconds - elapsedWithoutMatch)
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled else { return }
                if let live = ExtensionEventBus.shared.currentPayload(for: rule.trigger),
                   rule.conditions.allSatisfy({ $0.isSatisfied(by: live) }) {
                    elapsedWithoutMatch = 0
                    lastPayload = live
                } else {
                    elapsedWithoutMatch += step
                }
            }
            self.sustainTimers[ruleID] = nil
            self.handle(ExtensionTriggerEvent(id: .durationElapsed, payload: lastPayload))
        }
    }

    private func cancelSustainTimers(in record: ExtensionRecord) {
        for rule in record.rules {
            sustainTimers[rule.id]?.cancel()
            sustainTimers[rule.id] = nil
        }
    }

    /// Evaluates `rule.prerequisites` under `rule.mode`. Empty prerequisites
    /// always pass — the gate only exists once an author opts into it.
    private func prerequisitesPass(_ rule: ExtensionRule) -> Bool {
        guard !rule.prerequisites.isEmpty else { return true }
        switch rule.mode {
        case .entry:
            // Run if ANY prerequisite's live state currently matches its
            // payload; skip only if ALL currently mismatch.
            return rule.prerequisites.contains {
                ExtensionActionExecutor.currentlyMatches($0.action, payload: $0.payload)
            }
        case .exit:
            // Run if ANY prerequisite's live state currently mismatches its
            // payload; skip only if ALL currently match.
            return rule.prerequisites.contains {
                !ExtensionActionExecutor.currentlyMatches($0.action, payload: $0.payload)
            }
        }
    }
}
