import Foundation
import Defaults

struct ActiveDownload: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let browser: DownloadBrowserKind
    var bytesReceived: Int64
    var bytesExpected: Int64
    let startedAt: Date

    var progress: Double {
        guard bytesExpected > 0 else { return -1 }
        return min(1.0, Double(bytesReceived) / Double(bytesExpected))
    }

    static func == (lhs: ActiveDownload, rhs: ActiveDownload) -> Bool { lhs.id == rhs.id }
}

enum DownloadBrowserKind {
    case safari, chrome, unknown
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [ActiveDownload] = []
    var hasActiveDownloads: Bool { !activeDownloads.isEmpty }

    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads")
    private var idCache: [String: UUID] = [:]

    private init() {
        if Defaults[.enableDownloadListener] { start() }
    }

    func start() {
        guard directorySource == nil else { return }
        let fd = open(downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        directorySource = source

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scan()
    }

    func stop() {
        directorySource?.cancel()
        directorySource = nil
        pollTimer?.invalidate()
        pollTimer = nil
        activeDownloads = []
        idCache = [:]
    }

    private func scan() {
        guard Defaults[.enableDownloadListener] else { activeDownloads = []; return }

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey]
        ) else { return }

        var found: [ActiveDownload] = []

        for item in items {
            let name = item.lastPathComponent

            if name.hasSuffix(".crdownload") {
                let baseName = String(name.dropLast(".crdownload".count))
                if let attrs = try? fm.attributesOfItem(atPath: item.path),
                   let size = attrs[.size] as? Int64,
                   let created = attrs[.creationDate] as? Date {
                    found.append(ActiveDownload(
                        id: stableID(for: item.path),
                        fileName: baseName.isEmpty ? name : baseName,
                        browser: .chrome,
                        bytesReceived: size,
                        bytesExpected: -1,
                        startedAt: created
                    ))
                }
            } else if name.hasSuffix(".download") && Defaults[.enableSafariDownloads] {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir, let dl = parseSafariDownload(item) {
                    found.append(dl)
                }
            }
        }

        activeDownloads = found
    }

    private func parseSafariDownload(_ bundleURL: URL) -> ActiveDownload? {
        let fm = FileManager.default
        let baseName = String(bundleURL.lastPathComponent.dropLast(".download".count))
        let created = (try? fm.attributesOfItem(atPath: bundleURL.path))?[.creationDate] as? Date ?? Date()
        let plistURL = bundleURL.appendingPathComponent("Info.plist")

        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(
               from: data, options: [], format: nil
           ) as? [String: Any] {
            let name = (plist["DownloadEntryPath"] as? String)
                .flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? baseName
            let received = plist["DownloadEntryProgressBytesSoFar"] as? Int64 ?? 0
            let expected = plist["DownloadEntryProgressTotalToLoad"] as? Int64 ?? -1
            return ActiveDownload(
                id: stableID(for: bundleURL.path), fileName: name,
                browser: .safari, bytesReceived: received, bytesExpected: expected,
                startedAt: created
            )
        }

        return ActiveDownload(
            id: stableID(for: bundleURL.path),
            fileName: baseName.isEmpty ? bundleURL.lastPathComponent : baseName,
            browser: .safari, bytesReceived: 0, bytesExpected: -1, startedAt: created
        )
    }

    private func stableID(for path: String) -> UUID {
        if let e = idCache[path] { return e }
        let new = UUID(); idCache[path] = new; return new
    }
}
