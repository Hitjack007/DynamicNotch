import Testing
import Foundation
@testable import DynamicNotch

/// Covers the behavior change from ExtensionPersistenceService silently
/// dropping any extension that failed to decode: broken entries must now
/// load as `.unreadable` (never dropped) and survive being saved back
/// alongside other, valid extensions.
@Suite("ExtensionPersistenceService")
struct ExtensionPersistenceServiceTests {

    private func makeService() -> (service: ExtensionPersistenceService, fileURL: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtensionPersistenceServiceTests-\(UUID().uuidString).json")
        return (ExtensionPersistenceService(fileURL: url), url)
    }

    @Test("A mix of a readable and an unreadable record loads both, instead of dropping the unreadable one")
    func loadsMixOfReadableAndUnreadable() throws {
        let (service, url) = makeService()
        defer { try? FileManager.default.removeItem(at: url) }

        let json = """
        [
            { "id": "\(UUID().uuidString)", "name": "Good", "summary": "", "enabled": true, "rules": [], "createdAt": "2023-11-14T22:13:20Z" },
            { "id": "\(UUID().uuidString)", "name": "Broken", "summary": "", "enabled": true, "rules": [{ "trigger": "not.a.real.trigger", "actions": [] }], "createdAt": "2023-11-14T22:13:20Z" }
        ]
        """
        try Data(json.utf8).write(to: url)

        let items = service.load()
        #expect(items.count == 2)

        guard case .readable(let record) = items[0] else {
            Issue.record("Expected the first item to be readable")
            return
        }
        #expect(record.name == "Good")

        guard case .unreadable(let unreadable) = items[1] else {
            Issue.record("Expected the second item to be unreadable rather than dropped")
            return
        }
        #expect(unreadable.name == "Broken")
        #expect(unreadable.reason.contains("not.a.real.trigger"))
    }

    @Test("Saving preserves an unreadable record's content instead of dropping it")
    func saveRoundTripsUnreadableRecord() throws {
        let (service, url) = makeService()
        defer { try? FileManager.default.removeItem(at: url) }

        let brokenID = UUID()
        let unreadable = UnreadableExtension(
            id: brokenID,
            name: "Broken",
            summary: "",
            reason: "doesn't matter for this test",
            rawJSON: Data(#"{ "id": "\#(brokenID.uuidString)", "name": "Broken", "rules": [{ "trigger": "not.a.real.trigger", "actions": [] }] }"#.utf8)
        )
        let readable = ExtensionRecord(name: "Good")

        // Saving alongside another extension is exactly what happens today when
        // someone toggles or edits anything else while a broken extension sits
        // in the list — that's the save call that used to erase it.
        service.save([.readable(readable), .unreadable(unreadable)])
        let reloaded = service.load()

        #expect(reloaded.count == 2)
        #expect(reloaded.contains { $0.id == readable.id && $0.record != nil })

        guard let reloadedBroken = reloaded.first(where: { $0.id == brokenID }) else {
            Issue.record("Expected the broken record to still be present after a save")
            return
        }
        guard case .unreadable(let stillUnreadable) = reloadedBroken else {
            Issue.record("Expected the broken record to still be unreadable, not silently \"fixed\" or lost")
            return
        }
        #expect(stillUnreadable.name == "Broken")
    }

    @Test("A file that isn't a JSON array is backed up instead of silently discarded")
    func backsUpNonArrayFile() throws {
        let (service, url) = makeService()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data(#"{ "notAnArray": true }"#.utf8).write(to: url)

        let items = service.load()
        #expect(items.isEmpty)

        let siblingFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let backups = siblingFiles.filter { $0.lastPathComponent.hasPrefix("extensions.corrupt-") }
        #expect(!backups.isEmpty, "Expected a backup of the unreadable file instead of it being silently lost")
        for backup in backups {
            try? FileManager.default.removeItem(at: backup)
        }
    }

    @Test("An unknown trigger id gets a friendly, specific reason instead of a raw decoder message")
    func describeGivesFriendlyMessageForUnknownTriggerID() {
        let json = Data(#"{ "trigger": "battery.foo", "actions": [] }"#.utf8)
        do {
            _ = try JSONDecoder().decode(ExtensionRule.self, from: json)
            Issue.record("Expected decoding an unknown trigger id to throw")
        } catch {
            #expect(ExtensionPersistenceService.describe(error) == "Uses trigger \"battery.foo\", which this version doesn't support.")
        }
    }
}
