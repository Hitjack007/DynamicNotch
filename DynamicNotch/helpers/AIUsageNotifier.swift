//
//  AIUsageNotifier.swift
//  DynamicNotch
//
//  Posts AI usage alerts as system notifications.
//
//  The app icon shown on the leading edge of a banner is fixed by the system —
//  there is no API to replace it. The thumbnail on the trailing edge is ours,
//  so the Apple Intelligence glyph used elsewhere in the notch is rendered to a
//  PNG and attached there.
//

import AppKit
import UserNotifications

final class AIUsageNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AIUsageNotifier()

    private override init() { super.init() }

    private let symbolName = "apple.intelligence"

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: - Posting

    func postThreshold(provider: String, threshold: Int, timeUntilReset: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider) usage at \(threshold)%"
        content.body = timeUntilReset == "--"
            ? "You are near the end of this window."
            : "Window resets in \(timeUntilReset)."
        content.sound = .default
        content.threadIdentifier = threadIdentifier(for: provider)
        attachSymbol(to: content, tint: threshold >= 100 ? .systemRed : .systemOrange, slot: "threshold")

        // Reusing the identifier per threshold replaces any stale banner for the
        // same event instead of stacking a second one.
        post(content, identifier: "aiusage.\(provider).threshold.\(threshold)")
    }

    func postWindowReset(provider: String, previousPeak: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider) usage window reset"
        content.body = "The window that just ended peaked at \(Int(previousPeak.rounded()))%."
        content.sound = .default
        content.threadIdentifier = threadIdentifier(for: provider)
        attachSymbol(to: content, tint: .systemGreen, slot: "reset")

        post(content, identifier: "aiusage.\(provider).reset")
    }

    private func threadIdentifier(for provider: String) -> String {
        "aiusage.\(provider)"
    }

    private func post(_ content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Thumbnail

    private func attachSymbol(to content: UNMutableNotificationContent, tint: NSColor, slot: String) {
        guard let url = renderSymbol(tint: tint, slot: slot),
              let attachment = try? UNNotificationAttachment(identifier: "", url: url, options: nil)
        else { return }
        content.attachments = [attachment]
    }

    /// Draws the symbol tinted onto a transparent canvas and writes it as a PNG.
    ///
    /// The filename is stable per slot rather than unique, so repeated alerts
    /// overwrite one file instead of littering the temp directory. The system
    /// takes its own copy when the attachment is created.
    private func renderSymbol(tint: NSColor, slot: String) -> URL? {
        let config = NSImage.SymbolConfiguration(pointSize: 96, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return nil }

        let canvas = NSSize(width: 128, height: 128)
        let image = NSImage(size: canvas)
        image.lockFocus()
        let rect = NSRect(
            x: (canvas.width - symbol.size.width) / 2,
            y: (canvas.height - symbol.size.height) / 2,
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: rect)
        // sourceAtop recolours whatever was just drawn without painting the
        // transparent background, which keeps template and non-template symbols
        // looking the same.
        tint.set()
        rect.fill(using: .sourceAtop)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dynamicnotch-aiusage-\(slot).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return url
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The app is an accessory app, but the settings window can be frontmost.
        [.banner, .sound]
    }
}
