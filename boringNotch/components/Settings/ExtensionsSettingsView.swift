//
//  ExtensionsSettingsView.swift
//  boringNotch
//
//  The "Extensions" settings section: a searchable list of stored
//  ExtensionRecords with an enable toggle, an edit button (opens
//  ExtensionEditorView for manual JSON editing), and an explicit, confirmed
//  delete per row. "+" opens the same editor in create mode.
//

import SwiftUI

/// Identifies which extension (if any) the editor sheet is open for.
private enum ExtensionEditorTarget: Identifiable {
    case new
    case existing(ExtensionRecord)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let record): return record.id.uuidString
        }
    }
}

struct ExtensionsSettings: View {
    @ObservedObject private var manager = ExtensionsManager.shared
    @State private var searchText = ""
    @State private var editorTarget: ExtensionEditorTarget?
    @State private var recordPendingDeletion: ExtensionRecord?

    private var filteredExtensions: [ExtensionRecord] {
        guard !searchText.isEmpty else { return manager.extensions }
        return manager.extensions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.summary.localizedCaseInsensitiveContains(searchText)
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
                        ForEach(filteredExtensions) { record in
                            ExtensionSettingsRow(
                                record: record,
                                onEditRequested: { editorTarget = .existing(record) },
                                onDeleteRequested: { recordPendingDeletion = record }
                            )
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
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(recordPendingDeletion?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { recordPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { recordPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let record = recordPendingDeletion {
                    manager.remove(record.id)
                }
                recordPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                recordPendingDeletion = nil
            }
        } message: {
            Text("This can't be undone. Anything it turned on (like Caffeine) will be reverted first if it supports that.")
        }
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

#Preview {
    ExtensionsSettings()
        .frame(width: 500, height: 400)
}
