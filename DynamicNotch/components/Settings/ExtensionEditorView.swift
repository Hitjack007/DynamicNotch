//
//  ExtensionEditorView.swift
//  DynamicNotch
//
//  Manual editing surface for one extension: name/summary fields plus a raw
//  JSON editor for its rules. This is intentionally the only way to author
//  rules right now — no picker-based form — so hand-typing JSON and pasting
//  JSON back from an external chatbot are the same code path as each other.
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

    let isNew: Bool
    let onSave: (ExtensionRecord) -> Void

    @State private var name: String
    @State private var summary: String
    @State private var jsonText: String
    @State private var parseError: String?
    @State private var parsedRules: [ExtensionRule] = []
    @State private var showingReference = false
    @State private var showingAIAgentPrompt = false
    /// Collapsed by default — the raw JSON is an advanced/fallback path;
    /// "Copy for AI Agent" is the primary one, so most people never need
    /// to see this at all.
    @State private var isRulesJSONExpanded = false
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
        self.isNew = isNew
        self.onSave = onSave
        self.originalID = record.id
        self.originalEnabled = record.enabled
        self.originalCreatedAt = record.createdAt
        _name = State(initialValue: record.name)
        _summary = State(initialValue: record.summary)
        let data = (try? Self.encoder.encode(record.rules)) ?? Data("[]".utf8)
        _jsonText = State(initialValue: String(data: data, encoding: .utf8) ?? "[]")
    }

    var body: some View {
        VStack(spacing: 0) {
            ExtensionEditorHeader(
                title: isNew ? "New Extension" : "Edit Extension",
                saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parseError != nil,
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
                    CopyForAIAgentButton {
                        showingAIAgentPrompt = true
                    }
                } footer: {
                    Text("Describe what you want, copy the generated prompt, then paste its answer back with \u{201C}Paste JSON\u{201D} below.")
                }

                Section {
                    RulesStatusView(
                        parseError: parseError,
                        parsedRules: parsedRules,
                        onRunNow: { rule in Task { await ExtensionsManager.shared.runNow(rule) } }
                    )
                    DisclosureGroup(isExpanded: $isRulesJSONExpanded) {
                        RulesJSONEditor(jsonText: $jsonText)
                            .padding(.top, 6)
                    } label: {
                        Text("Show Raw JSON")
                    }
                } header: {
                    RulesSectionHeader(
                        onShowReference: { showingReference = true },
                        onPasteJSON: {
                            if let string = NSPasteboard.general.string(forType: .string) {
                                jsonText = string
                            }
                        }
                    )
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 560)
        .onAppear { validate() }
        .onChange(of: jsonText) { _, _ in validate() }
        .sheet(isPresented: $showingReference) {
            ReferenceView()
        }
        .sheet(isPresented: $showingAIAgentPrompt) {
            AIAgentPromptSheet(currentRulesJSON: jsonText)
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

    // MARK: - Actions

    private func validate() {
        guard let data = jsonText.data(using: .utf8) else {
            parseError = "Couldn't read that as text."
            parsedRules = []
            return
        }
        do {
            let rules = try JSONDecoder().decode([ExtensionRule].self, from: data)
            if let ineligible = Self.firstIneligiblePrerequisite(in: rules) {
                parsedRules = []
                parseError = "\"\(ineligible.rawValue)\" has no readable state, so it can't be used in \"prerequisites\"."
                return
            }
            parsedRules = rules
            parseError = nil
        } catch {
            parsedRules = []
            parseError = Self.readableError(error)
        }
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
        guard parseError == nil else { return }
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

    private static func readableError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing \"\(key.stringValue)\"\(path.isEmpty ? "" : " in \(path)")."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.debugDescription.isEmpty ? "That isn't valid JSON." : context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// The sheet's title row + Cancel/Save — matches the header chrome used by
/// other ad-hoc sheets in this app (e.g. `AppPickerSheet`), rather than a
/// `NavigationStack` toolbar.
private struct ExtensionEditorHeader: View {
    let title: String
    let saveDisabled: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
            Button("Cancel", action: onCancel)
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
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

/// The primary path right now: opens `AIAgentPromptSheet` to describe what's
/// wanted and copy a ready-to-paste prompt for an external chatbot/LLM.
/// Prominent while on-device generation is disabled, and full-width so it
/// reads as the primary action in the sheet, not a small aside.
private struct CopyForAIAgentButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label("Copy for AI Agent", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }
}

/// Opened by "Copy for AI Agent": describe the automation in plain English,
/// then copy a prompt bundling that description with everything the app
/// supports. Copying shows a popup confirming the copy and instructing the
/// person to paste into a chatbot; dismissing that popup also dismisses this
/// sheet, since there's nothing left to do here once the prompt is copied.
private struct AIAgentPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentRulesJSON: String

    @State private var request = ""
    @State private var showingCopiedAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Describe Your Extension")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Cancel") { dismiss() }
            }

            Text("This gets bundled into a prompt with everything the app supports, ready to paste into ChatGPT, Claude, or any chatbot.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "e.g. \u{201C}Turn on Caffeine when Xcode is frontmost\u{201D}",
                text: $request, axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...6)

            Button(action: copyPrompt) {
                Label("Copy Prompt", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(width: 420, height: 300)
        .alert("Prompt Copied", isPresented: $showingCopiedAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Paste this into ChatGPT, Claude, or any chatbot, then come back and paste its answer with \u{201C}Paste JSON\u{201D}.")
        }
    }

    private func copyPrompt() {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRequest = trimmed.isEmpty ? "<describe what you want here>" : trimmed
        let prompt = CapabilityRegistry.chatbotPrompt(currentRulesJSON: currentRulesJSON, request: effectiveRequest)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        showingCopiedAlert = true
    }
}

/// The Rules section's header — always visible regardless of whether the
/// raw JSON disclosure below is expanded. "See Reference" and "Paste JSON"
/// are how someone gets an AI-generated rule into the app, so hiding them
/// alongside the JSON editor would defeat the point of collapsing it.
private struct RulesSectionHeader: View {
    let onShowReference: () -> Void
    let onPasteJSON: () -> Void

    var body: some View {
        HStack {
            Text("Rules")
            Spacer()
            Button("See Reference", action: onShowReference)
            Button("Paste JSON", action: onPasteJSON)
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
            .frame(minHeight: 180)
    }
}

/// Mutually-exclusive status above the JSON editor: a parse error, the
/// parsed rule list with per-rule "Run Now", or an empty-state hint.
private struct RulesStatusView: View {
    let parseError: String?
    let parsedRules: [ExtensionRule]
    let onRunNow: (ExtensionRule) -> Void

    var body: some View {
        if let parseError {
            Text(parseError)
                .font(.caption)
                .foregroundStyle(.red)
        } else if !parsedRules.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(parsedRules) { rule in
                        RulePreviewRow(rule: rule, onRunNow: { onRunNow(rule) })
                    }
                }
            }
            .frame(maxHeight: 90)
        } else {
            Text("No rules yet \u{2014} an empty array is fine.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RulePreviewRow: View {
    let rule: ExtensionRule
    let onRunNow: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Run Now", action: onRunNow)
                .font(.caption)
                .buttonStyle(.borderless)
        }
    }

    private var label: String {
        let actionLabels = rule.actions.map { CapabilityRegistry.action($0.action).label }.joined(separator: " + ")
        var text = "\(CapabilityRegistry.trigger(rule.trigger).label) \u{2192} \(actionLabels)"
        if !rule.prerequisites.isEmpty {
            text += " (\(rule.mode == .entry ? "entry" : "exit") gate)"
        }
        return text
    }
}

/// Read-only viewer for the full trigger/action list, with its own copy button.
private struct ReferenceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Triggers & Actions")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CapabilityRegistry.referenceText(), forType: .string)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(CapabilityRegistry.referenceText())
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(width: 520, height: 480)
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
