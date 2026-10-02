//
//  ExtensionsManager.swift
//  DynamicNotch
//
//  Owns the stored extension list and is the one place that turns a fired
//  ExtensionTriggerEvent into ExtensionActionExecutor calls. Deliberately no
//  priority system between extensions/rules — every enabled rule whose
//  trigger and conditions match just runs, independently.
//
//  Gating: once a rule's trigger+conditions match, its `prerequisites` (if
//  any) decide whether `actions` actually runs — see `PrerequisiteMode`.
//  An "exit" rule is otherwise just another ordinary rule with its own
//  trigger, gated by the same prerequisites in the opposite polarity, BUT
//  it additionally requires its extension's "entry" rule to have already
//  fired since any exit rule last fired — see `armedExtensions` below. An
//  extension can have several exit rules sharing one entry rule's arming;
//  whichever fires first disarms the rest. That's the one piece of
//  cross-dispatch state this file keeps; unlike `sustainTimers`, it's
//  persisted (via `Defaults[.armedExtensionIDs]`) rather than in-memory,
//  so a crash or relaunch between an entry rule arming and its exit rule
//  firing doesn't strand the extension "on" with no way to self-correct.
//
//  `extensions` holds `StoredExtension`, not `ExtensionRecord` — an entry
//  that failed to decode (see ExtensionPersistenceService) stays in the
//  list as `.unreadable` so it's visible in Settings, but `handle(_:)` below
//  only ever dispatches `.readable` records.
//

import Combine
import Defaults
import Foundation

@MainActor
final class ExtensionsManager: ObservableObject {
    static let shared = ExtensionsManager()

    @Published private(set) var extensions: [StoredExtension] = []

    private let store = ExtensionPersistenceService.shared
    private var eventCancellable: AnyCancellable?

    /// One in-flight countdown per rule with `sustainFor` set, keyed by `ExtensionRule.id`.
    /// In-memory only — timers don't survive a relaunch, they only arm once a matching
    /// event is actually observed while running. See `armSustainTimer`.
    private var sustainTimers: [UUID: Task<Void, Never>] = [:]

    /// Extensions (keyed by `ExtensionRecord.id`) whose `entry` rule has fired — matched its
    /// trigger/conditions and passed its own prerequisite gate, so its actions actually ran —
    /// since the last time any of that extension's `exit` rules fired. A record only appears
    /// here while "armed"; an `exit` rule's own gate (`prerequisitesPass`) is necessary but not
    /// sufficient for it to fire — it also needs its extension's id present here. Whichever of
    /// an extension's (possibly several) exit rules fires first removes the id, so the rest
    /// stay quiet until `entry` fires again. Backed directly by `Defaults[.armedExtensionIDs]`
    /// (not a separate in-memory copy) so every read sees the latest persisted value and every
    /// mutation through the usual `Set` methods (`.insert`, `.remove`, `.contains`) persists
    /// immediately — a relaunch mid-"on" doesn't lose track of which extensions are armed.
    private var armedExtensions: Set<UUID> {
        get { Defaults[.armedExtensionIDs] }
        set { Defaults[.armedExtensionIDs] = newValue }
    }

    private init() {
        extensions = store.load()
        pruneArmedExtensions()
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
        pruneArmedExtensions()
    }

    /// Drops any persisted `armedExtensionIDs` whose extension no longer exists (deleted
    /// through some path that didn't go through `remove(_:)`, or left over from before this
    /// state was persisted) — otherwise a stale id could sit in `Defaults` forever with
    /// nothing left to ever read or clear it.
    private func pruneArmedExtensions() {
        let liveIDs = Set(extensions.map(\.id))
        armedExtensions = armedExtensions.intersection(liveIDs)
    }

    // MARK: - CRUD

    func add(_ record: ExtensionRecord) {
        extensions.append(.readable(record))
        persist()
    }

    /// Also used to save a fixed-up `.unreadable` entry: matching by id
    /// turns it back into `.readable` in place.
    func update(_ record: ExtensionRecord) {
        guard let index = extensions.firstIndex(where: { $0.id == record.id }) else { return }
        if case .readable(let existing) = extensions[index] {
            cancelSustainTimers(in: existing)
        }
        // The edit may have changed what "entry" even means for this extension, so any
        // previously-armed state no longer necessarily reflects reality.
        armedExtensions.remove(record.id)
        extensions[index] = .readable(record)
        persist()
    }

    func remove(_ id: UUID) {
        if let item = extensions.first(where: { $0.id == id }), case .readable(let record) = item {
            cancelSustainTimers(in: record)
        }
        armedExtensions.remove(id)
        extensions.removeAll { $0.id == id }
        persist()
    }

    /// No-ops for an unreadable entry — there's nothing to enable.
    func setEnabled(_ id: UUID, enabled: Bool) {
        guard let index = extensions.firstIndex(where: { $0.id == id }),
              case .readable(var record) = extensions[index]
        else { return }
        if !enabled {
            cancelSustainTimers(in: record)
            armedExtensions.remove(id)
        }
        record.enabled = enabled
        extensions[index] = .readable(record)
        persist()
    }

    private func persist() {
        extensions = store.save(extensions)
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
        for item in extensions {
            guard case .readable(let record) = item, record.enabled else { continue }
            for rule in record.rules where rule.trigger == event.id {
                dispatch(rule, event: event, record: record)
            }
        }
    }

    private func dispatch(_ rule: ExtensionRule, event: ExtensionTriggerEvent, record: ExtensionRecord) {
        guard rule.matches(event) else { return }

        // Independent of prerequisites/actions below — re-arms every time this rule's own
        // trigger/conditions match, regardless of whether its gate passes this time.
        if let sustainFor = rule.sustainFor {
            armSustainTimer(rule: rule, seconds: sustainFor, payload: event.payload)
        }

        guard prerequisitesPass(rule) else {
            AppLogger.extensions.debug("Extension rule \(rule.id): trigger \(event.id.rawValue) matched but prerequisites gate blocked it")
            return
        }

        switch Self.armedGateDecision(mode: rule.mode, isCurrentlyArmed: armedExtensions.contains(record.id)) {
        case .skip:
            AppLogger.extensions.debug("Extension rule \(rule.id): exit trigger \(event.id.rawValue) matched and gate passed, but its entry rule hasn't fired yet — skipped")
            return
        case .run(let armedAfter):
            if armedAfter {
                armedExtensions.insert(record.id)
            } else {
                armedExtensions.remove(record.id)
            }
        }

        for step in rule.actions {
            Task {
                let result = await ExtensionActionExecutor.perform(step.action, payload: step.payload)
                if result.success {
                    AppLogger.extensions.info("Extension rule \(rule.id): action \(step.action.rawValue) succeeded (\(result.message ?? "no message"))")
                } else {
                    AppLogger.extensions.error("Extension rule \(rule.id): action \(step.action.rawValue) failed (\(result.message ?? "no message"))")
                }
            }
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

    /// Outcome of the post-`prerequisitesPass` "armed" gate (see `armedExtensions`), and the
    /// armed-state change to apply if the rule runs. Pulled out as a pure function of just
    /// `mode` and the current armed flag — unlike `prerequisitesPass` above, it touches no
    /// live system state, so it's unit-testable on its own; see ExtensionsManagerTests.
    enum ArmedGateDecision: Equatable {
        case run(armedAfter: Bool)
        case skip
    }

    /// `entry` always runs and arms; `exit` only runs (and disarms) if already armed —
    /// otherwise it's skipped, regardless of how many times its own trigger/gate matches.
    nonisolated static func armedGateDecision(mode: PrerequisiteMode, isCurrentlyArmed: Bool) -> ArmedGateDecision {
        switch mode {
        case .entry:
            return .run(armedAfter: true)
        case .exit:
            return isCurrentlyArmed ? .run(armedAfter: false) : .skip
        }
    }
}
