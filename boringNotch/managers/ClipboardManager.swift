//
//  ClipboardManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation

/// Polls NSPasteboard and pushes captured items into the shelf as clipboard history.
/// Self-manages start/stop via the clipboardHistoryEnabled Defaults key.
@MainActor
final class ClipboardManager {
    static let shared = ClipboardManager()

    private var pollingTask: Task<Void, Never>?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var settingsCancellable: AnyCancellable?

    private init() {
        settingsCancellable = Defaults.publisher(.clipboardHistoryEnabled)
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    if change.newValue {
                        self?.start()
                    } else {
                        self?.stop()
                    }
                }
            }

        if Defaults[.clipboardHistoryEnabled] {
            start()
        }
    }

    private func start() {
        guard pollingTask == nil else { return }
        // Snapshot current count so first poll doesn't capture stale clipboard content
        lastChangeCount = NSPasteboard.general.changeCount

        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                await self?.poll()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Polling

    private func poll() async {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if let item = await capture(from: pasteboard) {
            ShelfStateViewModel.shared.addClipboardItem(item)
        }
    }

    // MARK: - Content capture

    private func capture(from pasteboard: NSPasteboard) async -> ShelfItem? {
        // 1. File URL
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions)?.first as? URL {
            guard let bookmarkData = try? Bookmark(url: fileURL).data else { return nil }
            return ShelfItem(kind: .file(bookmark: bookmarkData), isTemporary: false, source: .clipboard)
        }

        // 2. Non-file URL
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           !url.isFileURL {
            return ShelfItem(kind: .link(url: url), isTemporary: false, source: .clipboard)
        }

        // 3. String — detect bare URLs, otherwise treat as text
        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let url = URL(string: trimmed),
               (url.scheme == "https" || url.scheme == "http"),
               url.host != nil {
                return ShelfItem(kind: .link(url: url), isTemporary: false, source: .clipboard)
            }
            return ShelfItem(kind: .text(string: trimmed), isTemporary: false, source: .clipboard)
        }

        // 4. Image — stored as a temporary PNG
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let pngData = image.pngData() {
            guard let tempURL = await TemporaryFileStorageService.shared.createTempFile(
                for: .data(pngData, suggestedName: "clipboard-image.png")
            ),
            let bookmarkData = try? Bookmark(url: tempURL).data else { return nil }
            return ShelfItem(kind: .file(bookmark: bookmarkData), isTemporary: true, source: .clipboard)
        }

        return nil
    }
}
