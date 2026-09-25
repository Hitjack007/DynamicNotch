import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct IdleWidgetConfigurationView: View {
    @Binding var leftWidget: IdleNotchWidget
    @Binding var rightWidget: IdleNotchWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            notchPreview
            Divider()
            widgetPalette
            HStack {
                Text("Tap a chip to fill the next empty slot, or drag onto a slot directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") {
                    withAnimation { leftWidget = .none; rightWidget = .none }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Notch-shaped preview

    private var notchPreview: some View {
        HStack(spacing: 0) {
            WidgetSlot(widget: $leftWidget, label: "Left")
            Spacer()
            ZStack(alignment: .top) {
                Color.clear.frame(height: 44)
                NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
                    .fill(.black)
                    .frame(width: 80, height: 24)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
            Spacer()
            WidgetSlot(widget: $rightWidget, label: "Right")
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Widget palette

    private var widgetPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Widgets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(IdleNotchWidget.allCases.filter { $0 != .none }, id: \.self) { widget in
                        widgetChip(widget)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.visible)
        }
    }

    @ViewBuilder
    private func widgetChip(_ widget: IdleNotchWidget) -> some View {
        let isAssigned = leftWidget == widget || rightWidget == widget
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isAssigned
                          ? Color.effectiveAccent.opacity(0.15)
                          : Color(NSColor.controlBackgroundColor))
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isAssigned ? Color.effectiveAccent.opacity(0.5) : Color.clear,
                                lineWidth: 1
                            )
                    )
                Image(systemName: widget.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isAssigned ? Color.effectiveAccent : Color.primary)
            }
            .onDrag { NSItemProvider(object: NSString(string: "widget:\(widget.rawValue)")) }
            .onTapGesture {
                withAnimation {
                    if leftWidget == .none { leftWidget = widget }
                    else if rightWidget == .none { rightWidget = widget }
                    else { leftWidget = widget }
                }
            }
            Text(widget.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

// MARK: - Slot Drop Target

private struct WidgetSlot: View {
    @Binding var widget: IdleNotchWidget
    let label: String
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted
                      ? Color.effectiveAccent.opacity(0.12)
                      : Color(NSColor.controlBackgroundColor))
                .frame(width: 70, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isTargeted
                                ? Color.effectiveAccent
                                : (widget == .none
                                   ? Color.secondary.opacity(0.3)
                                   : Color.clear),
                            style: StrokeStyle(
                                lineWidth: 1.5,
                                dash: widget == .none ? [5, 3] : []
                            )
                        )
                )

            if widget != .none {
                VStack(spacing: 3) {
                    Image(systemName: widget.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primary)
                    Text(widget.label)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $isTargeted) { providers in
            for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                    let raw = (item as? NSString).map { $0 as String } ?? ""
                    DispatchQueue.main.async {
                        guard raw.hasPrefix("widget:") else { return }
                        let val = String(raw.dropFirst("widget:".count))
                        if let w = IdleNotchWidget(rawValue: val) {
                            withAnimation { widget = w }
                        }
                    }
                }
                return true
            }
            return false
        }
        .onTapGesture {
            if widget != .none { withAnimation { widget = .none } }
        }
        .help(widget == .none ? "Drag a widget here" : "\(widget.label) — tap to clear")
    }
}
