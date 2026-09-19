//
//  AmbientActivityOrderView.swift
//  boringNotch
//
//  Lets the user reorder which ambient closed-notch activity
//  (Music/Download/Face/AI Usage) wins when more than one is active. See
//  AmbientActivityResolver for how this order is resolved at render time.
//

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct AmbientActivityOrderView: View {
    @Default(.ambientActivityOrder) private var ambientActivityOrder
    @Default(.musicLiveActivityEnabled) private var musicLiveActivityEnabled
    @Default(.enableDownloadListener) private var downloadLiveActivityEnabled
    @Default(.showNotHumanFace) private var showFaceAnimation
    @Default(.aiUsageInNotch) private var aiUsageInNotch
    @Default(.showAIUsageTab) private var showAIUsageTab
    @State private var draggedActivity: AmbientActivity?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drag to reorder — the first active one wins the notch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation {
                        ambientActivityOrder = [.music, .download, .face, .aiUsage]
                    }
                }
                .buttonStyle(.borderless)
            }

            ForEach(Array(ambientActivityOrder.enumerated()), id: \.element) { index, activity in
                row(for: activity, at: index)
            }
        }
        .onAppear {
            let normalized = AmbientActivityResolver.normalize(ambientActivityOrder)
            if normalized != ambientActivityOrder {
                ambientActivityOrder = normalized
            }
        }
    }

    private func row(for activity: AmbientActivity, at index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Image(systemName: activity.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20)

            Text(activity.label)

            if !isEnabledElsewhere(activity) {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor), in: Capsule())
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onDrag {
            DispatchQueue.main.async { draggedActivity = activity }
            return NSItemProvider(object: NSString(string: "ambient:\(activity.rawValue)"))
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            let handled = handleDrop(providers, toIndex: index)
            DispatchQueue.main.async { draggedActivity = nil }
            return handled
        }
    }

    /// Whether this activity is enabled by its own feature toggle, so a
    /// disabled activity's position in the list doesn't look like a bug.
    private func isEnabledElsewhere(_ activity: AmbientActivity) -> Bool {
        switch activity {
        case .music:    return musicLiveActivityEnabled
        case .download: return downloadLiveActivityEnabled
        case .face:     return showFaceAnimation
        case .aiUsage:  return aiUsageInNotch && showAIUsageTab
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], toIndex: Int) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, _ in
                    if let nsstring = item as? NSString {
                        let raw = nsstring as String
                        DispatchQueue.main.async { processDropString(raw, toIndex: toIndex) }
                    } else if let str = item as? String {
                        DispatchQueue.main.async { processDropString(str, toIndex: toIndex) }
                    }
                }
                return true
            }
        }
        return false
    }

    private func processDropString(_ raw: String, toIndex: Int) {
        guard raw.hasPrefix("ambient:") else { return }
        let rawValue = String(raw.dropFirst("ambient:".count))
        guard let dragged = AmbientActivity(rawValue: rawValue) else { return }
        var current = ambientActivityOrder
        guard let fromIndex = current.firstIndex(of: dragged) else { return }
        current.swapAt(fromIndex, toIndex)
        withAnimation {
            ambientActivityOrder = current
        }
    }
}
