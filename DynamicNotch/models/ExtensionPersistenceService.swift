//
//  ExtensionPersistenceService.swift
//  DynamicNotch
//
//  One JSON array file for every stored extension, mirroring
//  ShelfPersistenceService's approach exactly: Application Support (so it
//  survives Sparkle updates, which only replace the .app bundle), atomic
//  writes, and per-item fallback decoding so one corrupted/out-of-date
//  extension (e.g. referencing a trigger/action id removed in a later
//  release) doesn't take the rest of the list down with it.
//
//  Per-item decode failures are never dropped: `load()` returns them as
//  `StoredExtension.unreadable`, carrying the original bytes, and `save()`
//  writes those bytes straight back — so a broken extension survives every
//  save until the person fixes or deletes it themselves.
//
//  The reverse direction (a record that fails to *encode*) is handled the
//  same way in spirit: `save()` returns the possibly-adjusted list so the
//  caller can update its published state, converting any unencodable record
//  into an `.unreadable` entry instead of silently omitting it from the
//  file. Unlike a decode failure, there's no already-valid JSON to fall
//  back to, so whatever can still be salvaged is written to a separate
//  quarantine file for later inspection.
//

import Foundation

final class ExtensionPersistenceService {
    static let shared = ExtensionPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        if support == nil {
            AppLogger.extensions.fault("ExtensionPersistenceService: could not resolve Application Support directory, falling back to temporary directory (extensions will not survive a reboot)")
        }
        let dir = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("extensions.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    /// Test-only entry point: points at an arbitrary file instead of the
    /// real Application Support location.
    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> [StoredExtension] {
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.extensions.debug("ExtensionPersistenceService: no existing extensions.json (first run or none saved yet)")
            return []
        }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            AppLogger.extensions.error("ExtensionPersistenceService: extensions.json is not a valid JSON array, backing up and starting fresh")
            backUp(data)
            return []
        }

        return jsonArray.map { jsonItem in
            let itemData = (try? JSONSerialization.data(withJSONObject: jsonItem)) ?? Data()
            do {
                return .readable(try decoder.decode(ExtensionRecord.self, from: itemData))
            } catch {
                AppLogger.extensions.error("ExtensionPersistenceService: one extension failed to decode, \(Self.describe(error))")
                return .unreadable(Self.unreadableExtension(from: jsonItem, rawJSON: itemData, error: error))
            }
        }
    }

    /// Returns the list back, with any record that failed to encode replaced
    /// by an `.unreadable` entry — callers should assign this back to their
    /// own published state (see `ExtensionsManager.persist()`) so a
    /// quarantined record shows up in the list immediately, instead of just
    /// quietly missing from the next launch.
    @discardableResult
    func save(_ items: [StoredExtension]) -> [StoredExtension] {
        var objects: [Any] = []
        let result: [StoredExtension] = items.map { item in
            switch item {
            case .readable(let record):
                do {
                    let data = try encoder.encode(record)
                    objects.append(try JSONSerialization.jsonObject(with: data))
                    return item
                } catch {
                    AppLogger.extensions.error("ExtensionPersistenceService: extension \(record.id) failed to encode, quarantining, \(Self.describe(error))")
                    return .unreadable(quarantine(record, error: error))
                }
            case .unreadable(let unreadable):
                if let object = try? JSONSerialization.jsonObject(with: unreadable.rawJSON) {
                    objects.append(object)
                }
                return item
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.extensions.error("ExtensionPersistenceService: failed to write extensions.json, \(type(of: error))")
        }
        return result
    }

    /// A record that fails to encode has no already-valid JSON to fall back
    /// to (unlike a load-time decode failure), so this retries once with a
    /// lenient float strategy — the one plausible real-world cause is a
    /// stray NaN/Infinity `Double` in a payload, which the default `.throw`
    /// strategy rejects — before giving up and quarantining just the
    /// identifying fields. Either way, the result is written to its own
    /// dated file rather than silently vanishing from `extensions.json`.
    private func quarantine(_ record: ExtensionRecord, error: Error) -> UnreadableExtension {
        let lenientEncoder = JSONEncoder()
        lenientEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        lenientEncoder.dateEncodingStrategy = .iso8601
        lenientEncoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")

        let rawJSON: Data
        if let rescued = try? lenientEncoder.encode(record) {
            rawJSON = rescued
        } else {
            rawJSON = (try? JSONSerialization.data(withJSONObject: [
                "id": record.id.uuidString, "name": record.name, "summary": record.summary,
            ], options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        }

        let quarantineURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("extensions.quarantine-\(record.id.uuidString).json")
        try? rawJSON.write(to: quarantineURL)

        return UnreadableExtension(
            id: record.id,
            name: record.name,
            summary: record.summary,
            reason: "Couldn't be saved (\(Self.describe(error))) — a copy was written to \(quarantineURL.lastPathComponent).",
            rawJSON: rawJSON
        )
    }

    /// Copies an unparseable file aside before anything can overwrite it —
    /// otherwise the very next `save()` (triggered by, say, toggling an
    /// unrelated extension) would replace it with an empty array.
    private func backUp(_ data: Data) {
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("extensions.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: backupURL)
    }

    private static func unreadableExtension(from jsonItem: Any, rawJSON: Data, error: Error) -> UnreadableExtension {
        let object = jsonItem as? [String: Any]
        let id = (object?["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let name = (object?["name"] as? String) ?? "Unreadable Extension"
        let summary = (object?["summary"] as? String) ?? ""
        return UnreadableExtension(id: id, name: name, summary: summary, reason: describe(error), rawJSON: rawJSON)
    }

    // MARK: - Error text

    /// Shared between persistence (for the list's unreadable-row subtitle)
    /// and `ExtensionEditorView` (for its inline parse error), so a broken
    /// extension always describes itself the same way.
    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing \"\(key.stringValue)\"\(path.isEmpty ? "" : " in \(path)")."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            if let friendly = friendlyUnknownIDMessage(context.debugDescription) {
                return friendly
            }
            return context.debugDescription.isEmpty ? "That isn't valid JSON." : context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }

    /// Swift's synthesized `Decodable` for a `String`-backed enum throws
    /// exactly "Cannot initialize <Type> from invalid String value <value>"
    /// for an unrecognized raw value — rewritten here since an unknown
    /// trigger/action id (renamed or removed in a later release) is the
    /// single most common way a stored extension goes unreadable.
    private static func friendlyUnknownIDMessage(_ debugDescription: String) -> String? {
        let prefix = "Cannot initialize "
        let separator = " from invalid String value "
        guard debugDescription.hasPrefix(prefix),
              let separatorRange = debugDescription.range(of: separator)
        else { return nil }
        let typeStart = debugDescription.index(debugDescription.startIndex, offsetBy: prefix.count)
        let type = debugDescription[typeStart..<separatorRange.lowerBound]
        let value = debugDescription[separatorRange.upperBound...]
        let kind: String
        switch type {
        case "TriggerID": kind = "trigger"
        case "ActionID": kind = "action"
        default: kind = "value"
        }
        return "Uses \(kind) \"\(value)\", which this version doesn't support."
    }
}
