import Testing
import Foundation
@testable import DynamicNotch

// MARK: - Helpers

/// Reads the bundled installer script as text. The Swift side (ThermalDaemonClient) and the
/// shell side (install-thermal-daemon.sh) each hard-code the protocol version and socket path
/// independently — there's no shared constant, so nothing else catches them drifting apart.
private func installerScriptText() throws -> String {
    guard let path = Bundle.main.path(forResource: "install-thermal-daemon", ofType: "sh") else {
        throw TestFailure("install-thermal-daemon.sh was not found in the test host's bundle resources")
    }
    return try String(contentsOfFile: path, encoding: .utf8)
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Tests

@Suite("Thermal daemon protocol version and migration gate")
struct ThermalDaemonProtocolTests {

    @Test("The Swift client's protocol version matches the bundled daemon script's")
    func protocolVersionsMatch() throws {
        let script = try installerScriptText()
        guard let match = script.range(of: #"daemonProtocolVersion\s*=\s*(\d+)"#, options: .regularExpression) else {
            throw TestFailure("Could not find 'daemonProtocolVersion = N' in install-thermal-daemon.sh")
        }
        let digits = script[match].reversed().prefix { $0.isNumber }.reversed()
        let scriptVersion = Int(String(digits))
        #expect(scriptVersion == ThermalDaemonClient.currentProtocolVersion, "Bumping ThermalDaemonClient.currentProtocolVersion without bumping the script's own constant would make every daemon report itself as up to date when it isn't")
    }

    @Test("The daemon script listens on the exact socket path the Swift client dials")
    func socketPathsMatch() throws {
        let script = try installerScriptText()
        #expect(script.contains(#"sockPath = "/tmp/boringnotch-thermal.sock""#), "Client and daemon must agree on the Unix socket path or every status/set/auto call silently fails to connect")
    }

    @Test("The migration highlight's id is derived from the current protocol version")
    func migrationHighlightID() {
        #expect(WhatsNewCatalog.thermalDaemonMigrationHighlight.id == "thermalDaemonMigration-v\(ThermalDaemonClient.currentProtocolVersion)")
    }

    @Test("The migration highlight renders the unskippable gate, not a normal What's New button")
    func migrationHighlightAction() {
        if case .thermalDaemonMigrate = WhatsNewCatalog.thermalDaemonMigrationHighlight.action {
            // expected
        } else {
            Issue.record("thermalDaemonMigrationHighlight.action should be .thermalDaemonMigrate")
        }
    }

    @Test("The migration highlight is synthesized at launch, not part of the versioned release catalog")
    func migrationHighlightNotInReleases() {
        let allIDs = WhatsNewCatalog.releases.flatMap(\.highlights).map(\.id)
        #expect(!allIDs.contains(WhatsNewCatalog.thermalDaemonMigrationHighlight.id), "If this ever ends up in `releases`, it would also show up as a skippable What's New page instead of only through the unskippable gate")
    }

    @Test("pages(...) never surfaces the migration highlight, however lastSeen/currentVersion line up")
    func pagesNeverIncludeMigrationHighlight() {
        let migrationID = WhatsNewCatalog.thermalDaemonMigrationHighlight.id
        let pages = WhatsNewCatalog.pages(lastSeenVersion: "", currentVersion: "27.3")
        #expect(!pages.map(\.highlight.id).contains(migrationID))
    }
}
