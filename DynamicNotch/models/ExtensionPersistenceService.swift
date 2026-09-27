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

import Foundation

final class ExtensionPersistenceService {
    static let shared = ExtensionPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
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
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            print("⚠️ Extensions persistence file is not a valid JSON array")
            backUp(data)
            return []
        }

        return jsonArray.map { jsonItem in
            let itemData = (try? JSONSerialization.data(withJSONObject: jsonItem)) ?? Data()
            do {
                return .readable(try decoder.decode(ExtensionRecord.self, from: itemData))
            } catch {
                return .unreadable(Self.unreadableExtension(from: jsonItem, rawJSON: itemData, error: error))
            }
        }
    }

    func save(_ items: [StoredExtension]) {
        let objects: [Any] = items.compactMap { item -> Any? in
            switch item {
            case .readable(let record):
                guard let data = try? encoder.encode(record) else { return nil }
                return try? JSONSerialization.jsonObject(with: data)
            case .unreadable(let unreadable):
                return try? JSONSerialization.jsonObject(with: unreadable.rawJSON)
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save extensions: \(error.localizedDescription)")
        }
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
