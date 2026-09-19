//
//  ExtensionRecord.swift
//  boringNotch
//
//  The stored shape of one user extension: a name plus a flat list of
//  independent rules. Each rule is trigger -> (AND-only conditions) ->
//  (optional prerequisites gate) -> actions. There is deliberately no
//  cross-rule priority system — if someone wants a second, unrelated
//  behavior (or the "exit" side of a pair), that's a second rule with its
//  own trigger, not something derived from this one.
//  See project memory "Extensions Framework" for why.
//

import Foundation

/// A comparison against one field of a fired trigger's payload.
struct MatchCondition: Codable, Equatable, Sendable {
    enum Operator: String, Codable, CaseIterable, Sendable {
        case equals
        case notEquals
        case greaterThan
        case greaterThanOrEqual
        case lessThan
        case lessThanOrEqual
        case contains
    }

    var field: String
    var op: Operator
    var value: ExtensionValue

    /// Numeric operators compare `doubleValue`; `contains` compares
    /// `stringValue` case-insensitively; `equals`/`notEquals` compare the
    /// `ExtensionValue` directly so type mismatches (e.g. int vs string) are
    /// never accidentally equal.
    func isSatisfied(by payload: [String: ExtensionValue]) -> Bool {
        guard let actual = payload[field] else { return false }
        switch op {
        case .equals: return actual == value
        case .notEquals: return actual != value
        case .contains:
            guard let a = actual.stringValue, let b = value.stringValue else { return false }
            return a.localizedCaseInsensitiveContains(b)
        case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
            guard let a = actual.doubleValue, let b = value.doubleValue else { return false }
            switch op {
            case .greaterThan: return a > b
            case .greaterThanOrEqual: return a >= b
            case .lessThan: return a < b
            case .lessThanOrEqual: return a <= b
            default: return false
            }
        }
    }
}

/// One `action` + its `payload`. Used both for the actions a rule performs
/// and, reinterpreted as a read instead of a write, for `prerequisites` —
/// same wire shape either way, so authors only ever learn one shape.
struct ExtensionActionStep: Codable, Equatable, Sendable {
    var action: ActionID
    var payload: [String: ExtensionValue]

    init(action: ActionID, payload: [String: ExtensionValue] = [:]) {
        self.action = action
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case action, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(ActionID.self, forKey: .action)
        payload = try container.decodeIfPresent([String: ExtensionValue].self, forKey: .payload) ?? [:]
    }
}

/// How a rule's `prerequisites` gate its `actions`. Both read the exact same
/// prerequisite list; only the polarity of "satisfied" flips.
enum PrerequisiteMode: String, Codable, Sendable {
    /// Run if ANY prerequisite's live state currently matches its payload;
    /// skip only if ALL currently mismatch. Used for the "turn something on"
    /// side of a pair — e.g. only turn Caffeine on if it's currently off.
    case entry
    /// Run if ANY prerequisite's live state currently mismatches its
    /// payload; skip only if ALL currently match. Used for the "undo" side
    /// of a pair, reusing the exact same prerequisite list as its entry
    /// counterpart — e.g. only turn Caffeine off if it's currently on.
    case exit
}

struct ExtensionRule: Codable, Identifiable, Equatable {
    var id: UUID
    var trigger: TriggerID
    /// ANDed together. Empty means the rule matches on every occurrence of `trigger`.
    var conditions: [MatchCondition]
    /// Run in order once the trigger matches and `prerequisites` pass.
    var actions: [ExtensionActionStep]

    /// Ambient-state gate checked after `trigger`+`conditions` match, before
    /// `actions` run. Each entry is an `ActionID`+payload read back as live
    /// state instead of performed — only actions with real, comparable state
    /// (see `ActionDescriptor.prerequisiteEligible`) are legal here. Empty
    /// means no gate: `actions` run on every match, exactly as before this
    /// existed. `mode` decides the polarity — see `PrerequisiteMode`.
    var prerequisites: [ExtensionActionStep]
    var mode: PrerequisiteMode

    init(
        id: UUID = UUID(),
        trigger: TriggerID,
        conditions: [MatchCondition] = [],
        actions: [ExtensionActionStep],
        prerequisites: [ExtensionActionStep] = [],
        mode: PrerequisiteMode = .entry
    ) {
        self.id = id
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.prerequisites = prerequisites
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case id, trigger, conditions, actions, prerequisites, mode
    }

    /// Hand-typed or LLM-produced JSON shouldn't need to invent a UUID or
    /// spell out empty arrays — only `trigger` and `actions` are actually
    /// required on the wire.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try container.decode(TriggerID.self, forKey: .trigger)
        conditions = try container.decodeIfPresent([MatchCondition].self, forKey: .conditions) ?? []
        actions = try container.decode([ExtensionActionStep].self, forKey: .actions)
        prerequisites = try container.decodeIfPresent([ExtensionActionStep].self, forKey: .prerequisites) ?? []
        mode = try container.decodeIfPresent(PrerequisiteMode.self, forKey: .mode) ?? .entry
    }

    func matches(_ event: ExtensionTriggerEvent) -> Bool {
        guard event.id == trigger else { return false }
        return conditions.allSatisfy { $0.isSatisfied(by: event.payload) }
    }
}

struct ExtensionRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var summary: String = ""
    var enabled: Bool = true
    var rules: [ExtensionRule] = []
    var createdAt: Date = Date()
}
