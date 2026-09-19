//
//  ExtensionPersistenceService.swift
//  boringNotch
//
//  One JSON array file for every stored extension, mirroring
//  ShelfPersistenceService's approach exactly: Application Support (so it
//  survives Sparkle updates, which only replace the .app bundle), atomic
//  writes, and per-item fallback decoding so one corrupted/out-of-date
//  extension (e.g. referencing a trigger/action id removed in a later
//  release) doesn't take the rest of the list down with it.
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

    func load() -> [ExtensionRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        if let records = try? decoder.decode([ExtensionRecord].self, from: data) {
            return records
        }

        // Whole-array decode failed — likely one bad/out-of-date record.
        // Recover the rest instead of losing everything.
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            print("⚠️ Extensions persistence file is not a valid JSON array")
            return []
        }

        var validRecords: [ExtensionRecord] = []
        var failedCount = 0
        for (index, jsonItem) in jsonArray.enumerated() {
            do {
                let itemData = try JSONSerialization.data(withJSONObject: jsonItem)
                validRecords.append(try decoder.decode(ExtensionRecord.self, from: itemData))
            } catch {
                failedCount += 1
                print("⚠️ Failed to decode extension at index \(index): \(error.localizedDescription)")
            }
        }
        if failedCount > 0 {
            print("📦 Loaded \(validRecords.count) extensions, discarded \(failedCount) that failed to decode")
        }
        return validRecords
    }

    func save(_ records: [ExtensionRecord]) {
        do {
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save extensions: \(error.localizedDescription)")
        }
    }
}
