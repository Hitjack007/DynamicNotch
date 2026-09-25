//
//  ThermalDaemonClient.swift
//  DynamicNotch
//
//  Thin client for the BoringNotchThermalDaemon Unix-socket IPC.
//  Unix domain socket calls to a local daemon complete in < 2ms, so they
//  are safe to call synchronously from ThermalManager's main-actor context.
//

import AppKit
import Foundation

final class ThermalDaemonClient {
    static let shared = ThermalDaemonClient()
    private let socketPath = "/tmp/boringnotch-thermal.sock"
    private static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.boringnotch.thermaldaemon.plist"

    // Bump whenever a daemon change needs existing installs to be force-reinstalled.
    // Must match daemonProtocolVersion in Resources/install-thermal-daemon.sh.
    static let currentProtocolVersion = 2

    private(set) var isAvailable: Bool = false

    private init() {}

    // MARK: - Public API

    func checkAvailability() -> Bool {
        let r = send("status")
        isAvailable = r?.hasPrefix("ok") == true
        return isAvailable
    }

    /// Parses "daemonv=N" from the daemon's status reply. `nil` means either the daemon
    /// isn't reachable, or it predates version reporting entirely (the original,
    /// un-ramped script that shipped in every release through v27.4).
    func reportedProtocolVersion() -> Int? {
        guard let r = send("status"), let range = r.range(of: "daemonv=") else { return nil }
        let digits = r[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// True when the thermal daemon is installed (its launchd job exists on disk) but
    /// hasn't been confirmed to be running the current protocol version - either because
    /// it's still the old script, or because it isn't currently responding at all (e.g.
    /// crashed mid-update). `false` for anyone who has never installed the daemon.
    static var migrationNeeded: Bool {
        guard FileManager.default.fileExists(atPath: launchDaemonPlistPath) else { return false }
        guard let version = ThermalDaemonClient.shared.reportedProtocolVersion() else { return true }
        return version < currentProtocolVersion
    }

    /// Set all fans to the given RPM. Returns true if daemon accepted the command.
    @discardableResult
    func setFanRPM(_ rpm: Float) -> Bool {
        guard let r = send("set \(Int(rpm))") else { return false }
        return r.hasPrefix("ok")
    }

    /// Restore Apple automatic fan control.
    @discardableResult
    func setAutoFan() -> Bool {
        guard let r = send("auto") else { return false }
        return r.hasPrefix("ok")
    }

    // MARK: - Installer

    /// The App Sandbox blocks privileged AppleScript execution, so installing/reinstalling
    /// the daemon means copying a sudo command to the clipboard and opening Terminal for the
    /// user to run it. Shared between the Settings install flow and the What's New migration
    /// gate so there's one place that knows how to invoke the installer.
    enum Installer {
        /// Returns an error message on failure, or `nil` on success.
        static func copyCommandAndOpenTerminal() -> String? {
            guard let resourcePath = Bundle.main.resourcePath else {
                return "Could not locate app resources."
            }
            let scriptPath = (resourcePath as NSString).appendingPathComponent("install-thermal-daemon.sh")
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                return "Script not found — add install-thermal-daemon.sh to Copy Bundle Resources in Xcode."
            }
            // Kill the old daemon first (bootout for macOS 13+, pkill as fallback), then install fresh.
            let killCmd = "sudo launchctl bootout system/com.boringnotch.thermaldaemon 2>/dev/null; sudo pkill -f BoringNotchThermalDaemon 2>/dev/null; sleep 1"
            let cmd = "\(killCmd) && sudo bash '\(scriptPath)'"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            return nil
        }
    }

    // MARK: - Socket I/O

    @discardableResult
    private func send(_ command: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        // Must exceed the daemon's 600ms Ftst-unlock sleep (first set after auto resets unlocked=false)
        var tv = timeval(tv_sec: 0, tv_usec: 800_000)  // 800ms
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { cptr in
                socketPath.withCString { strncpy(cptr, $0, 103) }
            }
        }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            NSLog("ThermalDaemonClient: connect() failed errno=%d (%s)", errno, strerror(errno))
            isAvailable = false
            return nil
        }

        isAvailable = true

        let cmdBytes = Array((command + "\n").utf8)
        write(fd, cmdBytes, cmdBytes.count)

        var buf = [UInt8](repeating: 0, count: 256)
        let n = read(fd, &buf, 255)
        guard n > 0 else { return nil }

        return String(bytes: buf.prefix(Int(n)), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
