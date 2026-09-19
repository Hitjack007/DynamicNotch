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
        extensions[index] = record
        persist()
    }

    func remove(_ id: ExtensionRecord.ID) {
        extensions.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ id: ExtensionRecord.ID, enabled: Bool) {
        guard let index = extensions.firstIndex(where: { $0.id == id }) else { return }
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
        guard prerequisitesPass(rule) else { return }
        for step in rule.actions {
            Task { await ExtensionActionExecutor.perform(step.action, payload: step.payload) }
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
