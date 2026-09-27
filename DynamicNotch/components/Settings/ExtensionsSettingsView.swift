//
//  ExtensionsSettingsView.swift
//  DynamicNotch
//
//  The "Extensions" settings section: a searchable list of stored
//  ExtensionRecords with an enable toggle, an edit button (opens
//  ExtensionEditorView for manual JSON editing), and an explicit, confirmed
//  delete per row. "+" opens the same editor in create mode.
//
//  Extensions that failed to decode (see ExtensionPersistenceService) show
//  up as their own row with a warning triangle in place of the toggle —
//  they can't be enabled or run, only fixed or deleted.
//

import SwiftUI

/// Identifies which extension (if any) the editor sheet is open for.
private enum ExtensionEditorTarget: Identifiable {
    case new
    case existing(ExtensionRecord)
    case fix(UnreadableExtension)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let record): return record.id.uuidString
        case .fix(let unreadable): return unreadable.id.uuidString
        }
    }
}

struct ExtensionsSettings: View {
    @ObservedObject private var manager = ExtensionsManager.shared
    @State private var searchText = ""
    @State private var editorTarget: ExtensionEditorTarget?
    @State private var itemPendingDeletion: StoredExtension?

    private var filteredExtensions: [StoredExtension] {
        guard !searchText.isEmpty else { return manager.extensions }
        return manager.extensions.filter { item in
            if item.name.localizedCaseInsensitiveContains(searchText) { return true }
            if let record = item.record { return record.summary.localizedCaseInsensitiveContains(searchText) }
            return false
        }
    }

    var body: some View {
        Form {
            Section {
                if manager.extensions.isEmpty {
                    ContentUnavailableView(
                        "No Extensions Yet",
                        systemImage: "bolt.badge.a",
                        description: Text("Add one to automatically react to things like battery level, media playback, or which app is frontmost.")
                    )
                } else {
                    if manager.extensions.count > 5 {
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                    }
                    if filteredExtensions.isEmpty {
                        Text("No extensions match \u{201C}\(searchText)\u{201D}.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredExtensions) { item in
                            switch item {
                            case .readable(let record):
                                ExtensionSettingsRow(
                                    record: record,
                                    onEditRequested: { editorTarget = .existing(record) },
                                    onDeleteRequested: { itemPendingDeletion = item }
                                )
                            case .unreadable(let unreadable):
                                UnreadableExtensionRow(
                                    unreadable: unreadable,
                                    onFixRequested: { editorTarget = .fix(unreadable) },
                                    onDeleteRequested: { itemPendingDeletion = item }
                                )
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Your Extensions")
                    Spacer()
                    Button {
                        editorTarget = .new
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Extensions react to things this app already tracks and automatically run an action when they happen \u{2014} no coding required.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                ExtensionEditorView(record: ExtensionRecord(name: ""), isNew: true) { newRecord in
                    manager.add(newRecord)
                }
            case .existing(let record):
                ExtensionEditorView(record: record, isNew: false) { updated in
                    manager.update(updated)
                }
            case .fix(let unreadable):
                ExtensionEditorView(unreadable: unreadable) { fixed in
                    manager.update(fixed)
                }
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(itemPendingDeletion?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { itemPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = itemPendingDeletion {
                    manager.remove(item.id)
                }
                itemPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDeletion = nil
            }
        } message: {
            Text(deletionMessage)
        }
    }

    private var deletionMessage: String {
        if let item = itemPendingDeletion, item.record != nil {
            return "This can't be undone. Anything it turned on (like Caffeine) will be reverted first if it supports that."
        }
        return "This can't be undone."
    }
}

private struct ExtensionSettingsRow: View {
    @ObservedObject private var manager = ExtensionsManager.shared
    let record: ExtensionRecord
    let onEditRequested: () -> Void
    let onDeleteRequested: () -> Void

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { record.enabled },
            set: { manager.setEnabled(record.id, enabled: $0) }
        )
    }

    var body: some View {
        HStack {
            Toggle(isOn: isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onEditRequested) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit \(record.name)")

            Button(role: .destructive, action: onDeleteRequested) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete \(record.name)")
        }
    }

    private var subtitle: String {
        if !record.summary.isEmpty { return record.summary }
        if record.rules.isEmpty { return "No rules yet" }
        return "\(record.rules.count) rule\(record.rules.count == 1 ? "" : "s")"
    }
}

/// A stored extension that failed to decode. No toggle — it can't be
/// enabled or dispatched — just the reason it's broken and a way to fix or
/// remove it.
private struct UnreadableExtensionRow: View {
    let unreadable: UnreadableExtension
    let onFixRequested: () -> Void
    let onDeleteRequested: () -> Void

    var body: some View {
        HStack {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.medium)
                    .help(unreadable.reason)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unreadable.name)
                        .foregroundStyle(.secondary)
                    Text("Can't be loaded: \(unreadable.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Fix\u{2026}", action: onFixRequested)
                .buttonStyle(.borderless)

            Button(role: .destructive, action: onDeleteRequested) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete \(unreadable.name)")
        }
    }
}

#Preview {
    ExtensionsSettings()
        .frame(width: 500, height: 400)
}
