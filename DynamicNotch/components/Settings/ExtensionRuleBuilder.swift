//
//  ExtensionRuleBuilder.swift
//  DynamicNotch
//
//  Reusable pieces for the picker-based rule builder inside
//  ExtensionEditorView.swift: a big, searchable trigger/action picker
//  (CapabilityPickerButton — a plain native Picker menu is unreadable with
//  ~28 triggers/~19 actions), a payload field editor that dispatches on
//  PayloadFieldType to the right control, and the condition/action/
//  prerequisite row types built from those two.
//
//  Every row here is a thin, self-contained editor bound to a slice of the
//  same ExtensionRule the JSON editor reads and writes — there's no separate
//  "builder model"; picker edits and hand-typed JSON are always the same
//  ExtensionRule underneath.
//

import SwiftUI

// MARK: - Capability picker

/// A button that opens a searchable popover instead of a cramped native
/// `Picker` menu — the "big enough, searchable" requirement for choosing a
/// trigger or action out of a list that's too long to scan as a plain menu.
struct CapabilityPickerButton<ID: Hashable>: View {
    struct Item {
        let id: ID
        let idText: String
        let label: String
        let summary: String
    }

    let items: [Item]
    let selection: ID?
    let placeholder: String
    let onSelect: (ID) -> Void

    @State private var isPresented = false
    @State private var searchText = ""

    private var selectedItem: Item? { items.first { $0.id == selection } }

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
                || $0.idText.localizedCaseInsensitiveContains(searchText)
                || $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(selectedItem?.label ?? placeholder)
                    .foregroundStyle(selectedItem == nil ? .secondary : .primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $isPresented) {
            VStack(spacing: 0) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                Divider()
                List(filteredItems, id: \.id) { item in
                    Button {
                        onSelect(item.id)
                        isPresented = false
                        searchText = ""
                    } label: {
                        CapabilityRow(label: item.label, idText: item.idText, summary: item.summary, payloadFields: [], badges: [])
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(width: 340, height: 380)
        }
    }
}

extension CapabilityPickerButton where ID == TriggerID {
    static func forTriggers(selection: TriggerID?, onSelect: @escaping (TriggerID) -> Void) -> CapabilityPickerButton<TriggerID> {
        CapabilityPickerButton(
            items: CapabilityRegistry.triggers.map { Item(id: $0.id, idText: $0.id.rawValue, label: $0.label, summary: $0.summary) },
            selection: selection,
            placeholder: "Choose a trigger",
            onSelect: onSelect
        )
    }
}

extension CapabilityPickerButton where ID == ActionID {
    static func forActions(
        selection: ActionID?,
        restrictToPrerequisiteEligible: Bool = false,
        onSelect: @escaping (ActionID) -> Void
    ) -> CapabilityPickerButton<ActionID> {
        let descriptors = restrictToPrerequisiteEligible
            ? CapabilityRegistry.actions.filter(\.prerequisiteEligible)
            : CapabilityRegistry.actions
        return CapabilityPickerButton(
            items: descriptors.map { Item(id: $0.id, idText: $0.id.rawValue, label: $0.label, summary: $0.summary) },
            selection: selection,
            placeholder: "Choose an action",
            onSelect: onSelect
        )
    }
}

// MARK: - Payload field editor

/// Dispatches on `PayloadFieldType` to the right control, reading/writing
/// directly into a `[String: ExtensionValue]` payload dictionary keyed by
/// `field.key` — shared by action steps, prerequisites, and (via the value
/// half of `ConditionRow`) conditions.
struct PayloadFieldEditorView: View {
    let field: PayloadFieldDescriptor
    @Binding var payload: [String: ExtensionValue]

    var body: some View {
        switch field.type {
        case .bool:
            Toggle(field.label, isOn: boolBinding)
        case .string:
            TextField(field.label, text: stringBinding)
                .textFieldStyle(.roundedBorder)
        case .enumString(let options) where options.count <= 3:
            Picker(field.label, selection: stringBinding) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        case .enumString(let options):
            Picker(field.label, selection: stringBinding) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
        case .intRange(let range):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(field.label): \(intValue)")
                    .font(.caption)
                Slider(value: intProxyBinding, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            }
        case .doubleRange(let range):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(field.label): \(doubleDisplayValue(for: range))")
                    .font(.caption)
                if let step = field.step {
                    Slider(value: doubleBinding, in: range, step: step)
                } else {
                    Slider(value: doubleBinding, in: range)
                }
            }
        case .freeInt:
            TextField(field.label, value: intFreeBinding, format: .number)
                .textFieldStyle(.roundedBorder)
        case .freeDouble:
            TextField(field.label, value: doubleBinding, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var intValue: Int { payload[field.key]?.intValue ?? 0 }
    private var doubleValue: Double { payload[field.key]?.doubleValue ?? 0 }

    /// 0...1 ranges are always a fraction of "full" (volume, brightness, fan
    /// floor level, …) — showing them as a percentage reads far better than
    /// a raw "0.05" once the field also snaps in 5% steps.
    private func doubleDisplayValue(for range: ClosedRange<Double>) -> String {
        guard range == 0...1 else { return String(format: "%.2f", doubleValue) }
        return "\(Int((doubleValue * 100).rounded()))%"
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { payload[field.key]?.boolValue ?? false },
            set: { payload[field.key] = .bool($0) }
        )
    }
    private var stringBinding: Binding<String> {
        Binding(
            get: { payload[field.key]?.stringValue ?? "" },
            set: { payload[field.key] = .string($0) }
        )
    }
    private var doubleBinding: Binding<Double> {
        Binding(
            get: { payload[field.key]?.doubleValue ?? 0 },
            set: { payload[field.key] = .double($0) }
        )
    }
    private var intFreeBinding: Binding<Int> {
        Binding(
            get: { payload[field.key]?.intValue ?? 0 },
            set: { payload[field.key] = .int($0) }
        )
    }
    private var intProxyBinding: Binding<Double> {
        Binding(
            get: { Double(payload[field.key]?.intValue ?? 0) },
            set: { payload[field.key] = .int(Int($0.rounded())) }
        )
    }
}

// MARK: - Condition row

/// One entry in a rule's `conditions`: a field picker scoped to the rule's
/// current trigger's `payloadSchema` (a plain `Picker` is fine here — a
/// trigger has a handful of fields at most, not 28), an operator picker
/// filtered by that field's type, and a value editor.
struct ConditionRow: View {
    let trigger: TriggerID
    @Binding var condition: MatchCondition
    let onDelete: () -> Void

    private var fields: [PayloadFieldDescriptor] {
        CapabilityRegistry.trigger(trigger).payloadSchema
    }

    private var selectedField: PayloadFieldDescriptor? {
        fields.first { $0.key == condition.field }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Picker("Field", selection: fieldBinding) {
                        ForEach(fields, id: \.key) { field in
                            Text(field.label).tag(field.key)
                        }
                    }
                    .labelsHidden()

                    if let selectedField {
                        Picker("Operator", selection: $condition.op) {
                            ForEach(selectedField.type.applicableOperators, id: \.self) { op in
                                Text(op.displayName).tag(op)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if let selectedField, case .bool = selectedField.type {
                    // No separate value control for bool fields — "is"/
                    // "isn't" alone carries the polarity now (see
                    // `canonicalizeBoolValue()`). A checkbox captioned with
                    // the same field name shown by the picker above it read
                    // as comparing the field to itself, and paired with the
                    // operator it let you build a double negative (operator
                    // "isn't" + unchecked = the opposite of what either
                    // control looks like it says).
                } else if let selectedField {
                    PayloadFieldEditorView(field: selectedField, payload: valuePayloadBinding(for: selectedField))
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
        .onAppear(perform: canonicalizeBoolValue)
    }

    private var fieldBinding: Binding<String> {
        Binding(
            get: { condition.field },
            set: { newKey in
                condition.field = newKey
                if let newField = fields.first(where: { $0.key == newKey }) {
                    condition.op = newField.type.applicableOperators.first ?? .equals
                    if case .bool = newField.type {
                        condition.value = .bool(true)
                    } else {
                        condition.value = newField.type.defaultValue
                    }
                }
            }
        )
    }

    /// A `.bool` condition's `value` is always pinned to `true` — "is"/
    /// "isn't" alone expresses polarity. Rules saved before this existed (or
    /// hand-typed/generated JSON) can still have `value: false`; flipping
    /// the operator alongside pinning the value preserves what the
    /// condition actually matches instead of silently changing its meaning
    /// (equals+false and notEquals+true both mean "isn't", so they map to
    /// each other, not to a bare value flip).
    private func canonicalizeBoolValue() {
        guard let selectedField, case .bool = selectedField.type, condition.value != .bool(true) else { return }
        condition.op = condition.op == .equals ? .notEquals : .equals
        condition.value = .bool(true)
    }

    /// `PayloadFieldEditorView` reads/writes a `[String: ExtensionValue]`
    /// dictionary (shared with action-step payloads); a condition only has
    /// one bare `value`, so this adapts it into a single-entry dictionary
    /// keyed by the field, round-tripping back into `condition.value`.
    private func valuePayloadBinding(for field: PayloadFieldDescriptor) -> Binding<[String: ExtensionValue]> {
        Binding(
            get: { [field.key: condition.value] },
            set: { condition.value = $0[field.key] ?? condition.value }
        )
    }
}

// MARK: - Action step row

/// One entry in a rule's `actions`: an action picker plus a field editor
/// per `payloadSchema` entry. Shows an inline nudge with a one-click
/// "Scaffold" fix when this action is `prerequisiteEligible` but isn't yet
/// gated by the owning rule's `prerequisites`.
struct ActionStepRow: View {
    @Binding var step: ExtensionActionStep
    let onDelete: () -> Void
    let missingPrerequisiteGate: Bool
    let onScaffoldPrerequisite: () -> Void

    private var descriptor: ActionDescriptor { CapabilityRegistry.action(step.action) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CapabilityPickerButton<ActionID>.forActions(selection: step.action) { newID in
                    step = ExtensionActionStep(action: newID)
                }
                if let boolField = descriptor.singleBoolField {
                    OnOffInlineToggle(field: boolField, payload: $step.payload)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            if descriptor.singleBoolField == nil {
                ForEach(descriptor.payloadSchema, id: \.key) { field in
                    PayloadFieldEditorView(field: field, payload: $step.payload)
                }
            }
            if missingPrerequisiteGate {
                InlineNudgeRow(
                    message: "This can drift out of sync unless it's gated.",
                    actionTitle: "Scaffold",
                    onAction: onScaffoldPrerequisite
                )
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }
}

/// One entry in a rule's `prerequisites` — same shape as `ActionStepRow`
/// but restricted to `prerequisiteEligible` actions and with no nudge of
/// its own (a prerequisite entry IS the gate; it doesn't need one).
struct PrerequisiteRow: View {
    @Binding var step: ExtensionActionStep
    let onDelete: () -> Void

    private var descriptor: ActionDescriptor { CapabilityRegistry.action(step.action) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CapabilityPickerButton<ActionID>.forActions(selection: step.action, restrictToPrerequisiteEligible: true) { newID in
                    step = ExtensionActionStep(action: newID)
                }
                if let boolField = descriptor.singleBoolField {
                    OnOffInlineToggle(field: boolField, payload: $step.payload)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            if descriptor.singleBoolField == nil {
                ForEach(descriptor.payloadSchema, id: \.key) { field in
                    PayloadFieldEditorView(field: field, payload: $step.payload)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }
}

/// Compact "On/Off" segmented control shown inline next to the action
/// picker when the action's whole payload is a single Bool (see
/// `ActionDescriptor.singleBoolField`) — replaces a separate "Enabled"
/// checkbox row so e.g. "Turn Caffeine on/off" reads as one control, not two.
private struct OnOffInlineToggle: View {
    let field: PayloadFieldDescriptor
    @Binding var payload: [String: ExtensionValue]

    var body: some View {
        Picker("", selection: binding) {
            Text("On").tag(true)
            Text("Off").tag(false)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 96)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { payload[field.key]?.boolValue ?? true },
            set: { payload[field.key] = .bool($0) }
        )
    }
}

// MARK: - Rule mutation helpers

/// Shared between the compact `RuleSummaryRow` (its inline scaffold button)
/// and the full `RuleDetailEditorView` (its "Add Condition"/"Add Gate"/"Add
/// Action" buttons) in ExtensionEditorView.swift, so both ways of touching a
/// rule scaffold the exact same starting point.
extension ExtensionRule {
    mutating func addCondition() {
        guard let firstField = CapabilityRegistry.trigger(trigger).payloadSchema.first else { return }
        let value: ExtensionValue
        if case .bool = firstField.type {
            value = .bool(true)
        } else {
            value = firstField.type.defaultValue
        }
        conditions.append(MatchCondition(
            field: firstField.key,
            op: firstField.type.applicableOperators.first ?? .equals,
            value: value
        ))
    }

    mutating func addPrerequisite() {
        guard let firstEligible = CapabilityRegistry.actions.first(where: \.prerequisiteEligible) else { return }
        prerequisites.append(ExtensionActionStep(action: firstEligible.id))
    }

    mutating func addAction() {
        guard let firstAction = CapabilityRegistry.actions.first else { return }
        actions.append(ExtensionActionStep(action: firstAction.id))
    }

    /// Shared by `scaffoldPrerequisite` (adds a new gate) and
    /// `fixRedundantPrerequisite` (repairs one that already exists but got
    /// the polarity wrong): starts from the action step's own payload, then
    /// negates every `.bool` field (relative to that field's own
    /// `boolDefault`, matching the executor's `?? default` fallback) — an
    /// "entry" gate needs the *opposite* state of what the action sets, not
    /// the same one (see TIPS: turning something on is gated on it currently
    /// being off). Non-bool fields (e.g. a target volume level) have no
    /// well-defined opposite, so they're carried over unchanged for the user
    /// to review.
    private static func negatedGatePayload(from actionPayload: [String: ExtensionValue], for actionID: ActionID) -> [String: ExtensionValue] {
        var gatePayload = actionPayload
        for field in CapabilityRegistry.action(actionID).payloadSchema {
            guard case .bool = field.type else { continue }
            let current = gatePayload[field.key]?.boolValue ?? field.boolDefault
            gatePayload[field.key] = .bool(!current)
        }
        return gatePayload
    }

    /// The one-click fix behind the inline "needs a prerequisite gate" nudge.
    mutating func scaffoldPrerequisite(for actionID: ActionID) {
        guard !prerequisites.contains(where: { $0.action == actionID }) else { return }
        let actionPayload = actions.first { $0.action == actionID }?.payload ?? [:]
        prerequisites.append(ExtensionActionStep(action: actionID, payload: Self.negatedGatePayload(from: actionPayload, for: actionID)))
    }

    /// The one-click fix behind the inline "gate matches its own action"
    /// nudge (see `actionsWithRedundantPrerequisite`): re-derives the
    /// existing gate's payload from scratch instead of leaving it as-is,
    /// since a hand-edited or generated gate can get here by copying the
    /// action's payload verbatim rather than negating it.
    mutating func fixRedundantPrerequisite(for actionID: ActionID) {
        guard let index = prerequisites.firstIndex(where: { $0.action == actionID }) else { return }
        let actionPayload = actions.first { $0.action == actionID }?.payload ?? [:]
        prerequisites[index].payload = Self.negatedGatePayload(from: actionPayload, for: actionID)
    }

    /// Actions in `actions` whose matching `prerequisites` entry has the
    /// same `.bool` field value(s) as the action itself — a gate that can
    /// only ever pass when the action would already be a no-op (see TIPS).
    /// Only meaningful in `entry` mode: an `exit`-mode rule built by
    /// `makingExitCounterpart()` deliberately sets the action's payload to
    /// match its own prerequisite, so equality there is the correct,
    /// intended shape, not a bug.
    var actionsWithRedundantPrerequisite: [ActionID] {
        guard mode == .entry else { return [] }
        return actions.compactMap { action in
            guard let prerequisite = prerequisites.first(where: { $0.action == action.action }) else { return nil }
            let schema = CapabilityRegistry.action(action.action).payloadSchema
            let isRedundant = schema.contains { field in
                guard case .bool = field.type else { return false }
                let actionValue = action.payload[field.key]?.boolValue ?? field.boolDefault
                let prerequisiteValue = prerequisite.payload[field.key]?.boolValue ?? field.boolDefault
                return actionValue == prerequisiteValue
            }
            return isRedundant ? action.action : nil
        }
    }

    /// A starting point for this rule's "undo" counterpart — per TIPS, an
    /// entry/exit pair reuses the exact same `prerequisites` (only `mode`
    /// flips), so this copies them as-is instead of leaving them empty for
    /// someone to rebuild from scratch. Each action's payload is swapped for
    /// its matching prerequisite's payload where one exists (that's the
    /// state being restored to); actions with no matching prerequisite are
    /// copied unchanged for review. The trigger defaults to
    /// `.durationElapsed` when `sustainFor` is set (the paired trigger TIPS
    /// describes for that pattern) or the same trigger otherwise — either
    /// way it's worth reviewing, since there's no safe way to guess whether
    /// "undo" really means the same event, app quit, thermal normal, or a
    /// timer.
    func makingExitCounterpart() -> ExtensionRule {
        let exitActions = actions.map { step -> ExtensionActionStep in
            guard let matchingPrerequisite = prerequisites.first(where: { $0.action == step.action }) else { return step }
            return ExtensionActionStep(action: step.action, payload: matchingPrerequisite.payload)
        }
        return ExtensionRule(
            trigger: sustainFor != nil ? .durationElapsed : trigger,
            conditions: conditions,
            actions: exitActions,
            prerequisites: prerequisites,
            mode: .exit
        )
    }
}

/// A small orange-triangle callout with a one-tap fix — used for the
/// per-action-step "needs a prerequisite gate" nudge. The record-level
/// "fan floor has no exit rule" banner in ExtensionEditorView.swift is
/// visually louder (it can block Save on its own) and defined there instead.
struct InlineNudgeRow: View {
    let message: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(actionTitle, action: onAction)
                .font(.caption)
                .buttonStyle(.borderless)
        }
    }
}
