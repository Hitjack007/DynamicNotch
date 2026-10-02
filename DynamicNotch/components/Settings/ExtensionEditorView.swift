//
//  ExtensionEditorView.swift
//  DynamicNotch
//
//  Manual editing surface for one extension: name/summary fields, an
//  inline "describe it / copy a prompt / paste the reply" flow for an
//  external chatbot, plain-language rule cards, and a raw JSON editor as
//  the advanced/fallback path. Hand-typing JSON and pasting JSON back from
//  a chatbot are the same code path as each other.
//
//  On-device generation (ExtensionGenerationService) is implemented but
//  disabled here for now — see the commented-out `generationSection`/
//  `generate()` below — so the prompt-copy workflow is the primary path
//  until that's revisited.
//

import AppKit
import SwiftUI

struct ExtensionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let headerTitle: String
    let onSave: (ExtensionRecord) -> Void

    @State private var name: String
    @State private var summary: String
    @State private var jsonText: String
    @State private var parseError: String?
    @State private var parsedRules: [ExtensionRule] = []
    /// Non-decode problems from `CapabilityRegistry.issues(in:)` — kept
    /// separate from `parseError` because these don't blank out
    /// `parsedRules`; the whole point is to keep showing the rule (with its
    /// inline nudge/scaffold) so it can be fixed in place.
    @State private var safetyIssues: [String] = []
    @State private var showingReference = false
    /// Collapsed by default — the raw JSON is an advanced/fallback path;
    /// the describe/copy/paste flow above it is the primary one, so most
    /// people never need to see this at all.
    @State private var isRulesJSONExpanded: Bool

    // "Build with AI" flow state. Collapsed by default — manual, picker-based
    // creation is the primary path now; AI assistance and raw JSON are both
    // secondary, collapsed disclosures underneath the rule list.
    @State private var isBuildWithAIExpanded = false
    @State private var request = ""
    @State private var showingCopiedConfirmation = false
    @State private var pendingPasteText: String?
    @State private var showingPasteReplaceConfirmation = false
    @State private var pasteError: String?

    // Run Now confirmation — this performs real actions immediately, even
    // on unsaved JSON, so it always asks first.
    @State private var rulePendingRun: ExtensionRule?

    /// Set right after appending a new rule (via "Add Rule" or "Add Exit
    /// Rule") so its `RuleSummaryRow` opens the full editor immediately
    /// instead of requiring a second click to find it.
    @State private var ruleIDPendingAutoOpen: UUID?

    // On-device generation state — kept for when generationSection/generate()
    // below are re-enabled.
    // @State private var generationRequest = ""
    // @State private var isGenerating = false
    // @State private var generationMessage: String?

    private let originalID: UUID
    private let originalEnabled: Bool
    private let originalCreatedAt: Date

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(record: ExtensionRecord, isNew: Bool, onSave: @escaping (ExtensionRecord) -> Void) {
        self.headerTitle = isNew ? "New Extension" : "Edit Extension"
        self.onSave = onSave
        self.originalID = record.id
        self.originalEnabled = record.enabled
        self.originalCreatedAt = record.createdAt
        _name = State(initialValue: record.name)
        _summary = State(initialValue: record.summary)
        let data = (try? Self.encoder.encode(record.rules)) ?? Data("[]".utf8)
        _jsonText = State(initialValue: String(data: data, encoding: .utf8) ?? "[]")
        _isRulesJSONExpanded = State(initialValue: false)
    }

    /// Opened from "Fix…" on a broken list row: preloads whatever rules
    /// JSON could be recovered from the raw bytes so the parse error shows
    /// immediately, with the raw JSON section already expanded.
    init(unreadable: UnreadableExtension, onSave: @escaping (ExtensionRecord) -> Void) {
        self.headerTitle = "Fix Extension"
        self.onSave = onSave
        self.originalID = unreadable.id
        self.originalEnabled = true
        self.originalCreatedAt = Date()
        _name = State(initialValue: unreadable.name)
        _summary = State(initialValue: unreadable.summary)
        _jsonText = State(initialValue: Self.rulesJSONText(from: unreadable.rawJSON))
        _isRulesJSONExpanded = State(initialValue: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            ExtensionEditorHeader(
                title: headerTitle,
                saveDisabledReason: saveDisabledReason,
                onCancel: { dismiss() },
                onSave: save
            )
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            Form {
                Section {
                    ExtensionDetailsFields(name: $name, summary: $summary)
                } header: {
                    Text("Details")
                }

                Section {
                    RulesStatusView(
                        parseError: parseError,
                        parsedRules: $parsedRules,
                        ruleIDPendingAutoOpen: $ruleIDPendingAutoOpen,
                        onRunNow: { rule in rulePendingRun = rule },
                        onAddRule: addRule,
                        onRemoveRule: removeRule,
                        onScaffoldExitRule: scaffoldExitRule,
                        onAddExitCounterpart: addExitCounterpart
                    )

                    // Both secondary/advanced authoring paths — collapsed by default,
                    // manual picker-based creation above is the primary path.
                    DisclosureGroup(isExpanded: $isBuildWithAIExpanded) {
                        buildWithAIContent
                    } label: {
                        Text("Build with AI")
                    }
                    DisclosureGroup(isExpanded: $isRulesJSONExpanded) {
                        RulesJSONEditor(jsonText: $jsonText)
                            .padding(.top, 6)
                    } label: {
                        Text("Edit JSON")
                    }
                } header: {
                    RulesSectionHeader(rulesCount: parsedRules.count, onShowReference: { showingReference = true })
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 560)
        .frame(minHeight: 520, idealHeight: 640, maxHeight: 820)
        .onAppear { validate() }
        .onChange(of: jsonText) { _, _ in validate() }
        .onChange(of: parsedRules) { _, _ in syncJSONFromParsedRules() }
        .sheet(isPresented: $showingReference) {
            ReferenceView()
        }
        .confirmationDialog(
            "Replace the existing rules?",
            isPresented: $showingPasteReplaceConfirmation
        ) {
            Button("Replace", role: .destructive) { applyPendingPaste() }
            Button("Cancel", role: .cancel) { pendingPasteText = nil }
        } message: {
            Text("This extension already has \(parsedRules.count) rule\(parsedRules.count == 1 ? "" : "s"). Pasting will replace \(parsedRules.count == 1 ? "it" : "them").")
        }
        .confirmationDialog(
            "Run this rule now?",
            isPresented: Binding(
                get: { rulePendingRun != nil },
                set: { isPresented in if !isPresented { rulePendingRun = nil } }
            )
        ) {
            Button("Run", role: .destructive) {
                if let rule = rulePendingRun {
                    Task { await ExtensionsManager.shared.runNow(rule) }
                }
                rulePendingRun = nil
            }
            Button("Cancel", role: .cancel) { rulePendingRun = nil }
        } message: {
            Text("This performs its actions immediately, even though you haven\u{2019}t saved yet.")
        }
    }

    // MARK: - On-device generation (disabled — see file header)
    //
    // @ViewBuilder
    // private var generationSection: some View {
    //     switch ExtensionGenerationService.availability {
    //     case .available:
    //         VStack(alignment: .leading, spacing: 6) {
    //             HStack(alignment: .top) {
    //                 TextField(
    //                     "Describe what you want, e.g. \u{201C}turn on Caffeine when Xcode is frontmost\u{201D}",
    //                     text: $generationRequest, axis: .vertical
    //                 )
    //                 .textFieldStyle(.roundedBorder)
    //                 .lineLimit(1...3)
    //                 .onSubmit { Task { await generate() } }
    //
    //                 Button {
    //                     Task { await generate() }
    //                 } label: {
    //                     if isGenerating {
    //                         ProgressView()
    //                             .controlSize(.small)
    //                             .frame(width: 40)
    //                     } else {
    //                         Text("Generate")
    //                     }
    //                 }
    //                 .disabled(isGenerating || generationRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    //             }
    //             if let generationMessage {
    //                 Text(generationMessage)
    //                     .font(.caption)
    //                     .foregroundStyle(.secondary)
    //             }
    //         }
    //     case .unavailable(let reason):
    //         Text(reason)
    //             .font(.caption)
    //             .foregroundStyle(.secondary)
    //     }
    // }
    //
    // private func generate() async {
    //     guard !isGenerating else { return }
    //     isGenerating = true
    //     generationMessage = nil
    //     defer { isGenerating = false }
    //
    //     do {
    //         let result = try await ExtensionGenerationService.generate(
    //             request: generationRequest,
    //             currentRulesJSON: jsonText
    //         )
    //         switch result.status {
    //         case "needsClarification":
    //             generationMessage = result.clarifyingQuestion.isEmpty
    //                 ? "Could you be more specific?"
    //                 : result.clarifyingQuestion
    //         case "cannotBuild":
    //             generationMessage = result.reason.isEmpty
    //                 ? "This app can't do that yet."
    //                 : result.reason
    //         default:
    //             if !result.name.isEmpty { name = result.name }
    //             if !result.summary.isEmpty { summary = result.summary }
    //             jsonText = Self.prettyPrinted(result.rulesJSON)
    //         }
    //     } catch {
    //         generationMessage = error.localizedDescription
    //     }
    // }
    //
    // private static func prettyPrinted(_ rawJSON: String) -> String {
    //     guard let data = rawJSON.data(using: .utf8),
    //           let object = try? JSONSerialization.jsonObject(with: data),
    //           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    //           let string = String(data: pretty, encoding: .utf8)
    //     else { return rawJSON }
    //     return string
    // }

    // MARK: - Build with AI

    @ViewBuilder
    private var buildWithAIContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            BuildWithAIStep(
                stepNumber: 1,
                title: "Describe what it should do",
                content: {
                    TextField(
                        "e.g. \u{201C}Turn on Caffeine when Xcode is frontmost\u{201D}",
                        text: $request, axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                    HStack(spacing: 8) {
                        Button(action: copyPrompt) {
                            Label("Copy Prompt", systemImage: "doc.on.clipboard")
                        }
                        if showingCopiedConfirmation {
                            Text("Copied \u{2014} paste into any chatbot")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            )

            BuildWithAIStep(
                stepNumber: 2,
                title: "Paste its reply",
                content: {
                    HStack(spacing: 8) {
                        Button(action: requestPaste) {
                            Label("Paste Reply", systemImage: "doc.on.clipboard.fill")
                        }
                        if let pasteError {
                            Text(pasteError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            )

            Text("Bundles your description with everything this app supports, ready to paste into ChatGPT, Claude, or any chatbot.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func copyPrompt() {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRequest = trimmed.isEmpty ? "<describe what you want here>" : trimmed
        let prompt = CapabilityRegistry.chatbotPrompt(currentRulesJSON: jsonText, request: effectiveRequest)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        showingCopiedConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            showingCopiedConfirmation = false
        }
    }

    private func requestPaste() {
        pasteError = nil
        guard let string = NSPasteboard.general.string(forType: .string) else {
            pasteError = "Clipboard doesn't contain any text."
            return
        }
        pendingPasteText = string
        if parsedRules.isEmpty {
            applyPendingPaste()
        } else {
            showingPasteReplaceConfirmation = true
        }
    }

    private func applyPendingPaste() {
        guard let pendingPasteText else { return }
        jsonText = pendingPasteText
        self.pendingPasteText = nil
    }

    // MARK: - Actions

    private func validate() {
        guard let data = jsonText.data(using: .utf8) else {
            parseError = "Couldn't read that as text."
            parsedRules = []
            safetyIssues = []
            return
        }
        do {
            let rules = try JSONDecoder().decode([ExtensionRule].self, from: data)
            if let ineligible = Self.firstIneligiblePrerequisite(in: rules) {
                parsedRules = []
                safetyIssues = []
                parseError = "\"\(ineligible.rawValue)\" has no readable state, so it can't be used in \"prerequisites\"."
                return
            }
            parseError = nil
            parsedRules = rules
            safetyIssues = CapabilityRegistry.issues(in: rules)
        } catch {
            parsedRules = []
            safetyIssues = []
            parseError = Self.describeRulesError(error)
        }
    }

    /// Re-encodes `parsedRules` back into `jsonText` whenever a picker edit
    /// mutates a rule in place (the JSON editor's own edits flow the other
    /// direction, through `validate()` above) — the two views never drift
    /// because they always resolve to the same encoded string. Also keeps
    /// `safetyIssues` current for edits that didn't go through `validate()`.
    ///
    /// Guarded on `parseError == nil`: `validate()` clears `parsedRules` to
    /// `[]` on any parse failure, which is also a change `onChange` sees —
    /// without this guard, typing through a momentarily-invalid JSON string
    /// (deleting a bracket to paste a new rule, etc.) would round-trip
    /// straight back through here and overwrite the in-progress text with
    /// "[]". Only sync when the last parse actually succeeded.
    private func syncJSONFromParsedRules() {
        guard parseError == nil else { return }
        safetyIssues = CapabilityRegistry.issues(in: parsedRules)
        guard let data = try? Self.encoder.encode(parsedRules) else { return }
        jsonText = String(data: data, encoding: .utf8) ?? jsonText
    }

    private func addRule() {
        guard let firstTrigger = CapabilityRegistry.triggers.first, let firstAction = CapabilityRegistry.actions.first else { return }
        let newRule = ExtensionRule(trigger: firstTrigger.id, actions: [ExtensionActionStep(action: firstAction.id)])
        parsedRules.append(newRule)
        ruleIDPendingAutoOpen = newRule.id
    }

    private func removeRule(at index: Int) {
        guard parsedRules.indices.contains(index) else { return }
        parsedRules.remove(at: index)
    }

    /// "Add Exit Rule" from inside a rule's own editor (as opposed to
    /// `scaffoldExitRule`, triggered from the record-level fanFloorSet
    /// banner) — reuses `ExtensionRule.makingExitCounterpart()` so the new
    /// rule starts with the same prerequisites instead of empty ones.
    private func addExitCounterpart(of rule: ExtensionRule) {
        let exitRule = rule.makingExitCounterpart()
        parsedRules.append(exitRule)
        ruleIDPendingAutoOpen = exitRule.id
    }

    /// Scaffolds an "exit" rule for a `requiresPairedExitRule` action that's
    /// currently on with nothing to turn it back off — finds the rule that
    /// turns it on and delegates to `makingExitCounterpart()`, the same
    /// helper `addExitCounterpart` uses, so both scaffold paths reuse the
    /// on-rule's own prerequisites instead of each rebuilding a gate from
    /// the action's payload (which gets the entry/exit polarity backwards).
    /// The trigger it inherits is still worth double-checking: there's no
    /// safe way to guess whether "undo" should really mean the same event,
    /// app quit, thermal normal, or a timer.
    private func scaffoldExitRule(for actionID: ActionID) {
        guard let onRule = parsedRules.first(where: { rule in
            rule.actions.contains { $0.action == actionID && ($0.payload["enabled"]?.boolValue ?? true) }
        }) else { return }
        let exitRule = onRule.makingExitCounterpart()
        parsedRules.append(exitRule)
        ruleIDPendingAutoOpen = exitRule.id
    }

    /// Returns the first `ActionID` used inside any rule's `prerequisites`
    /// that isn't `prerequisiteEligible` — e.g. a fire-and-forget command
    /// like `notification.request` with nothing persistent to compare
    /// against. `nil` means every prerequisite in every rule is legal.
    private static func firstIneligiblePrerequisite(in rules: [ExtensionRule]) -> ActionID? {
        for rule in rules {
            for step in rule.prerequisites where !CapabilityRegistry.action(step.action).prerequisiteEligible {
                return step.action
            }
        }
        return nil
    }

    private func save() {
        guard parseError == nil, safetyIssues.isEmpty else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onSave(ExtensionRecord(
            id: originalID,
            name: trimmedName,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            enabled: originalEnabled,
            rules: parsedRules,
            createdAt: originalCreatedAt
        ))
        dismiss()
    }

    private var saveDisabledReason: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a name to save."
        }
        if parseError != nil {
            return "Fix the rule error below to save."
        }
        if let firstIssue = safetyIssues.first {
            return safetyIssues.count == 1 ? firstIssue : "\(firstIssue) (+\(safetyIssues.count - 1) more)"
        }
        return nil
    }

    /// Prefixes a decode error with which rule caused it, when the JSON
    /// decoder's coding path starts with an array index — i.e. every case
    /// except a malformed top-level array.
    private static func describeRulesError(_ error: Error) -> String {
        let base = ExtensionPersistenceService.describe(error)
        guard let decodingError = error as? DecodingError,
              let ruleIndex = ruleIndex(in: decodingError)
        else { return base }
        return "Rule \(ruleIndex + 1): \(base)"
    }

    private static func ruleIndex(in error: DecodingError) -> Int? {
        switch error {
        case .keyNotFound(_, let context), .typeMismatch(_, let context),
             .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.first?.intValue
        @unknown default:
            return nil
        }
    }

    /// Recovers the `rules` array from a broken extension's raw bytes for
    /// preloading into the "Fix…" flow. Falls back to the whole object (or
    /// an empty array) if `rules` itself can't be isolated, so nothing the
    /// person needs to see is hidden.
    private static func rulesJSONText(from rawJSON: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any],
              let rules = object["rules"],
              let rulesData = try? JSONSerialization.data(withJSONObject: rules, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: rulesData, encoding: .utf8)
        else { return prettyPrinted(rawJSON) ?? "[]" }
        return string
    }

    private static func prettyPrinted(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}

/// The sheet's title row + Cancel/Save — matches the header chrome used by
/// other ad-hoc sheets in this app (e.g. `AppPickerSheet`), rather than a
/// `NavigationStack` toolbar. Shows why Save is disabled instead of just
/// disabling it silently.
private struct ExtensionEditorHeader: View {
    let title: String
    let saveDisabledReason: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabledReason != nil)
            }
            if let saveDisabledReason {
                Text(saveDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Name/summary text fields, styled like every other `Form`-embedded
/// `TextField` in Settings (e.g. the search field in `ExtensionsSettings`).
private struct ExtensionDetailsFields: View {
    @Binding var name: String
    @Binding var summary: String

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
        TextField("Summary (optional)", text: $summary)
            .textFieldStyle(.roundedBorder)
    }
}

/// One numbered step of the inline "Build with AI" flow — describe, then
/// paste the reply. Replaces the old two-sheet flow (a "Copy for AI Agent"
/// button opening a second sheet with its own text field and a closing
/// alert) with everything visible in the same place at once.
private struct BuildWithAIStep<Content: View>: View {
    let stepNumber: Int
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(stepNumber). \(title)")
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.bottom, stepNumber == 1 ? 4 : 0)
    }
}

private struct RulesSectionHeader: View {
    let rulesCount: Int
    let onShowReference: () -> Void

    var body: some View {
        HStack {
            Text(rulesCount > 0 ? "Rules (\(rulesCount))" : "Rules")
            Spacer()
            Button("Triggers & Actions Reference\u{2026}", action: onShowReference)
        }
    }
}

private struct RulesJSONEditor: View {
    @Binding var jsonText: String

    var body: some View {
        TextEditor(text: $jsonText)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            .frame(minHeight: 140)
    }
}

/// Mutually-exclusive status above the JSON editor: a parse error, or the
/// editable rule list (record-level safety banners, each rule as a picker
/// card, "Add Rule") — the parsed rules stay editable in place rather than
/// disappearing, so a fixable issue (missing gate, missing exit rule) can
/// actually be fixed from here instead of only being reported.
private struct RulesStatusView: View {
    let parseError: String?
    @Binding var parsedRules: [ExtensionRule]
    @Binding var ruleIDPendingAutoOpen: UUID?
    let onRunNow: (ExtensionRule) -> Void
    let onAddRule: () -> Void
    let onRemoveRule: (Int) -> Void
    let onScaffoldExitRule: (ActionID) -> Void
    let onAddExitCounterpart: (ExtensionRule) -> Void

    var body: some View {
        if let parseError {
            Text(parseError)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            let actionsNeedingExitRule = CapabilityRegistry.actionsRequiringExitRule(in: parsedRules)
            // An extension holds at most one entry rule (see CapabilityRegistry.issues(in:)),
            // but any number of exit rules, so only "Add Rule" (which always creates an entry-
            // mode rule) needs disabling here once one exists — exit rules aren't capped.
            let hasEntryRule = parsedRules.contains { $0.mode == .entry }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(actionsNeedingExitRule, id: \.self) { actionID in
                    RecordLevelNudgeBanner(
                        message: "\u{201C}\(CapabilityRegistry.action(actionID).label)\u{201D} is turned on but nothing in this extension turns it back off.",
                        actionTitle: "Add Exit Rule",
                        onAction: { onScaffoldExitRule(actionID) }
                    )
                }

                if parsedRules.isEmpty {
                    Text("No rules yet \u{2014} describe what you want above, add one below, or write JSON below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(parsedRules.indices), id: \.self) { index in
                        RuleSummaryRow(
                            rule: $parsedRules[index],
                            ruleIDPendingAutoOpen: $ruleIDPendingAutoOpen,
                            onRunNow: { onRunNow(parsedRules[index]) },
                            onDelete: { onRemoveRule(index) },
                            onAddExitCounterpart: onAddExitCounterpart,
                            onScaffoldExitRule: onScaffoldExitRule,
                            actionsNeedingExitRule: actionsNeedingExitRule.filter { actionID in
                                parsedRules[index].actions.contains { $0.action == actionID }
                            }
                        )
                    }
                }

                Button(action: onAddRule) {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(hasEntryRule)
                .help(hasEntryRule ? "This extension already has an entry rule \u{2014} an extension can have at most one." : "")
            }
        }
    }
}

/// A record-level (not per-rule) callout — used only for the
/// `requiresPairedExitRule` check, which spans every rule in the extension
/// rather than one. Visually louder than `InlineNudgeRow` (filled
/// background, prominent button) since it can block Save entirely.
private struct RecordLevelNudgeBanner: View {
    let message: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(actionTitle, action: onAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
    }
}

/// Compact, plain-language summary of one rule for the main list — trigger,
/// conditions, and actions as short lines, plus the inline "needs a gate"
/// nudge. This is deliberately not the full picker UI: that used to live
/// inline here, but nesting a `List` (for the reorderable THEN section)
/// inside this Form's own scroll view caused a scroll-to-top glitch on
/// click. Tap "Edit" to open the full builder in `RuleDetailEditorView`,
/// its own larger sheet, where the List is the outermost scrollable
/// container instead of nested inside another one.
private struct RuleSummaryRow: View {
    @Binding var rule: ExtensionRule
    @Binding var ruleIDPendingAutoOpen: UUID?
    let onRunNow: () -> Void
    let onDelete: () -> Void
    let onAddExitCounterpart: (ExtensionRule) -> Void
    let onScaffoldExitRule: (ActionID) -> Void
    /// This rule's own subset of `CapabilityRegistry.actionsRequiringExitRule` —
    /// shown here too (not just the outer list's banner) since someone deep
    /// in "Edit Rule" for this exact rule has no other way to see it's
    /// missing its exit counterpart.
    let actionsNeedingExitRule: [ActionID]

    @State private var isEditorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(triggerLine)
                        .font(.caption)
                    ForEach(actionLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button(action: onRunNow) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Run Now")
                Button(action: { isEditorPresented = true }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit Rule")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Rule")
            }
            ForEach(rule.actionsMissingPrerequisiteGate, id: \.self) { actionID in
                InlineNudgeRow(
                    message: "\u{201C}\(CapabilityRegistry.action(actionID).label)\u{201D} can drift out of sync unless it's gated.",
                    actionTitle: "Scaffold",
                    onAction: { rule.scaffoldPrerequisite(for: actionID) }
                )
            }
            ForEach(rule.actionsWithRedundantPrerequisite, id: \.self) { actionID in
                RecordLevelNudgeBanner(
                    message: "\u{201C}\(CapabilityRegistry.action(actionID).label)\u{201D}'s gate matches its own action \u{2014} it will never run except when it's already a no-op.",
                    actionTitle: "Fix Gate",
                    onAction: { rule.fixRedundantPrerequisite(for: actionID) }
                )
            }
            ForEach(actionsNeedingExitRule, id: \.self) { actionID in
                RecordLevelNudgeBanner(
                    message: "\u{201C}\(CapabilityRegistry.action(actionID).label)\u{201D} is turned on but nothing in this extension turns it back off.",
                    actionTitle: "Add Exit Rule",
                    onAction: { onScaffoldExitRule(actionID) }
                )
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        .onAppear {
            if ruleIDPendingAutoOpen == rule.id {
                isEditorPresented = true
                ruleIDPendingAutoOpen = nil
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            RuleDetailEditorView(
                rule: $rule,
                onRunNow: onRunNow,
                onAddExitCounterpart: { onAddExitCounterpart(rule) },
                onScaffoldExitRule: onScaffoldExitRule,
                actionsNeedingExitRule: actionsNeedingExitRule
            )
        }
    }

    private var triggerLine: String {
        var text = "When \(CapabilityRegistry.trigger(rule.trigger).label.lowercased())"
        if !rule.conditions.isEmpty {
            text += " (\(conditionsSummary))"
        }
        return text
    }

    private var conditionsSummary: String {
        rule.conditions.map { condition in
            "\(condition.field) \(condition.op.displayName) \(condition.value.stringValue ?? "null")"
        }.joined(separator: ", ")
    }

    private var actionLines: [String] {
        var lines = rule.actions.map { CapabilityRegistry.action($0.action).label }
        if !rule.prerequisites.isEmpty {
            let gateLabels = rule.prerequisites.map { CapabilityRegistry.action($0.action).label }.joined(separator: ", ")
            lines.append(rule.mode == .entry ? "Only if \(gateLabels) currently matches" : "Only if \(gateLabels) currently doesn't match")
        }
        if let sustainFor = rule.sustainFor {
            lines.append("Then fires again after \(Self.formatted(sustainFor)) without re-matching")
        }
        return lines
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }
}

/// A row identity unique across the whole `List` in `RuleDetailEditorView`,
/// not just within one section's array. Using a plain `Int` index as the id
/// (`id: \.self`) for more than one `ForEach` inside the same `List` is a
/// real bug, not a style nit: SwiftUI/AppKit's row-diffing keys off that id
/// across the *entire* List, so `conditions[0]`, `prerequisites[0]`, and
/// `actions[0]` all sharing the id `0` let it reuse/confuse one row's
/// content for another — which is exactly what caused the THEN section to
/// render an IF row's content on screen.
private struct RuleRowID: Hashable {
    let section: String
    let index: Int
}

/// The full picker builder for one rule — WHEN (trigger) / IF (conditions) /
/// ONLY IF (the prerequisite gate + entry/exit mode) / THEN (actions,
/// reorderable by drag) — opened as its own larger sheet instead of living
/// inline in the small editor's Form. One top-level `List` with four
/// sections: reordering the THEN section needs a `List`, and this way it's
/// the outermost scrollable container instead of nested inside the small
/// editor's Form (which is what caused the scroll-to-top glitch).
private struct RuleDetailEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var rule: ExtensionRule
    let onRunNow: () -> Void
    let onAddExitCounterpart: () -> Void
    let onScaffoldExitRule: (ActionID) -> Void
    /// Same as `RuleSummaryRow`'s — shown here too since this sheet, not the
    /// outer list, is where someone is actually looking while building this
    /// rule. Without this, "needs a prerequisite gate" was the only thing
    /// visible from in here, making the exit-rule requirement look
    /// unenforced even though Save was still blocked at the outer layer.
    let actionsNeedingExitRule: [ActionID]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Rule")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Add Exit Rule", action: onAddExitCounterpart)
                    .help("Add a paired rule that undoes this one \u{2014} same conditions and gate, mode flipped to exit.")
                Button(action: onRunNow) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Run Now")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            List {
                ForEach(rule.actionsWithRedundantPrerequisite, id: \.self) { actionID in
                    RecordLevelNudgeBanner(
                        message: "\u{201C}\(CapabilityRegistry.action(actionID).label)\u{201D}'s gate matches its own action \u{2014} it will never run except when it's already a no-op.",
                        actionTitle: "Fix Gate",
                        onAction: { rule.fixRedundantPrerequisite(for: actionID) }
                    )
                }
                ForEach(actionsNeedingExitRule, id: \.self) { actionID in
                    RecordLevelNudgeBanner(
                        message: "\u{201C}\(CapabilityRegistry.action(actionID).label)\u{201D} is turned on but nothing in this extension turns it back off.",
                        actionTitle: "Add Exit Rule",
                        onAction: { onScaffoldExitRule(actionID) }
                    )
                }

                Section {
                    CapabilityPickerButton<TriggerID>.forTriggers(selection: rule.trigger) { newTrigger in
                        rule.trigger = newTrigger
                        rule.conditions = []
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text("The event this rule reacts to.")
                }

                Section {
                    ForEach(rule.conditions.indices.map { RuleRowID(section: "condition", index: $0) }, id: \.self) { rowID in
                        ConditionRow(
                            trigger: rule.trigger,
                            condition: $rule.conditions[rowID.index],
                            onDelete: { rule.conditions.remove(at: rowID.index) }
                        )
                    }
                    Button("Add Condition") { rule.addCondition() }
                        .disabled(CapabilityRegistry.trigger(rule.trigger).payloadSchema.isEmpty)
                } header: {
                    Text("If (Conditions)")
                } footer: {
                    Text(rule.conditions.isEmpty
                        ? "Optional \u{2014} matches every occurrence of the trigger above. To match a specific app (e.g. Xcode), add a condition here."
                        : "All conditions must match (AND).")
                }

                Section {
                    ForEach(rule.prerequisites.indices.map { RuleRowID(section: "prerequisite", index: $0) }, id: \.self) { rowID in
                        PrerequisiteRow(
                            step: $rule.prerequisites[rowID.index],
                            onDelete: { rule.prerequisites.remove(at: rowID.index) }
                        )
                    }
                    Button("Add Gate") { rule.addPrerequisite() }
                } header: {
                    Text("Only If (Gate)")
                } footer: {
                    Text(rule.prerequisites.isEmpty
                        ? "Optional \u{2014} an ambient-state check, not a condition on the trigger. Leave empty unless an action below specifically needs one (you'll see a nudge if it does)."
                        : "Checked after the conditions above match, before the actions below run.")
                }

                Section {
                    ForEach(rule.actions.indices.map { RuleRowID(section: "action", index: $0) }, id: \.self) { rowID in
                        ActionStepRow(
                            step: $rule.actions[rowID.index],
                            onDelete: { rule.actions.remove(at: rowID.index) },
                            missingPrerequisiteGate: rule.actionsMissingPrerequisiteGate.contains(rule.actions[rowID.index].action),
                            onScaffoldPrerequisite: { rule.scaffoldPrerequisite(for: rule.actions[rowID.index].action) }
                        )
                    }
                    .onMove { indices, newOffset in
                        rule.actions.move(fromOffsets: indices, toOffset: newOffset)
                    }
                    Button("Add Action") { rule.addAction() }
                } header: {
                    Text("Then (Actions)")
                } footer: {
                    Text("What actually happens, in order, once everything above passes.")
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 640, height: 720)
    }
}

/// Structured, searchable viewer for the full trigger/action list — reads
/// `CapabilityRegistry`'s descriptors directly instead of scanning the flat
/// `referenceText()` string, so a label, its id, prose summary, and payload
/// fields each get their own visual treatment instead of one monospaced
/// wall of text (which is what made the old version barely readable: full
/// sentences don't wrap legibly in a fixed-width font). "Copy Plain Text"
/// still copies the flat format, since that's exactly what `chatbotPrompt`
/// embeds.
private struct ReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredTriggers: [TriggerDescriptor] {
        CapabilityRegistry.triggers.filter { matches($0.label, $0.id.rawValue, $0.summary) }
    }

    private var filteredActions: [ActionDescriptor] {
        CapabilityRegistry.actions.filter { matches($0.label, $0.id.rawValue, $0.summary) }
    }

    private func matches(_ strings: String...) -> Bool {
        guard !searchText.isEmpty else { return true }
        return strings.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Triggers & Actions")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Copy Plain Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CapabilityRegistry.referenceText(), forType: .string)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            TextField("Search triggers & actions", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            List {
                if searchText.isEmpty {
                    Section("Tips") {
                        ForEach(Array(CapabilityRegistry.tips.enumerated()), id: \.offset) { _, tip in
                            TipRow(text: tip)
                        }
                    }
                }

                if !filteredTriggers.isEmpty {
                    Section("Triggers (\(filteredTriggers.count))") {
                        ForEach(filteredTriggers, id: \.id) { descriptor in
                            CapabilityRow(
                                label: descriptor.label,
                                idText: descriptor.id.rawValue,
                                summary: descriptor.summary,
                                payloadFields: descriptor.payloadFields,
                                badges: []
                            )
                        }
                    }
                }

                if !filteredActions.isEmpty {
                    Section("Actions (\(filteredActions.count))") {
                        ForEach(filteredActions, id: \.id) { descriptor in
                            CapabilityRow(
                                label: descriptor.label,
                                idText: descriptor.id.rawValue,
                                summary: descriptor.summary,
                                payloadFields: descriptor.payloadFields,
                                badges: descriptor.prerequisiteEligible ? ["Usable as prerequisite"] : []
                            )
                        }
                    }
                }

                if !searchText.isEmpty && filteredTriggers.isEmpty && filteredActions.isEmpty {
                    Text("No matches for \u{201C}\(searchText)\u{201D}.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 560, height: 620)
    }
}

/// One trigger or action: a bold label with a monospaced id badge, its
/// summary in ordinary (non-monospaced) prose, and payload fields as small
/// code-styled captions below. Not `private` — also reused by
/// `CapabilityPickerButton` in ExtensionRuleBuilder.swift for its popover
/// rows, so the picker and the Reference view read identically.
struct CapabilityRow: View {
    let label: String
    let idText: String
    let summary: String
    let payloadFields: [String]
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout.bold())
                Spacer()
                IDBadge(text: idText)
            }
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !payloadFields.isEmpty {
                Text(payloadFields.joined(separator: "   "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ForEach(badges, id: \.self) { badge in
                Label(badge, systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct IDBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

private struct TipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ExtensionEditorView(
        record: ExtensionRecord(
            name: "Xcode Caffeine",
            rules: [
                ExtensionRule(
                    trigger: .appFrontmostChanged,
                    conditions: [MatchCondition(field: "name", op: .contains, value: .string("Xcode"))],
                    actions: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(true)])],
                    prerequisites: [ExtensionActionStep(action: .caffeineSet, payload: ["enabled": .bool(false)])],
                    mode: .entry
                )
            ]
        ),
        isNew: false
    ) { _ in }
}
