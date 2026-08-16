//
//  ThermalDaemonClient.swift
//  boringNotch
//
//  Thin client for the BoringNotchThermalDaemon Unix-socket IPC.
//  Unix domain socket calls to a local daemon complete in < 2ms, so they
//  are safe to call synchronously from ThermalManager's main-actor context.
//

import Foundation

final class ThermalDaemonClient {
    static let shared = ThermalDaemonClient()
    private let socketPath = "/tmp/boringnotch-thermal.sock"

    private(set) var isAvailable: Bool = false

    private init() {}

    // MARK: - Public API

    func checkAvailability() -> Bool {
        let r = send("status")
        isAvailable = r?.hasPrefix("ok") == true
        return isAvailable
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
