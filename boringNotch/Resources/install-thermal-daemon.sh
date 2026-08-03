#!/bin/bash
# install-thermal-daemon.sh
# Compiles the BoringNotch fan control daemon from embedded source and installs it.
# Must be run as root: sudo bash /path/to/install-thermal-daemon.sh

set -euo pipefail

INSTALL_DIR="/Library/BoringNotch"
DAEMON_DEST="$INSTALL_DIR/BoringNotchThermalDaemon"
PLIST_LABEL="com.boringnotch.thermaldaemon"
PLIST_DEST="/Library/LaunchDaemons/$PLIST_LABEL.plist"
TMP_SRC="/tmp/BoringNotchThermalDaemon_src.swift"

echo "Writing daemon source..."
cat > "$TMP_SRC" << 'SWIFTSRC'
import Foundation
import IOKit

private enum SMCCmd: UInt8 {
    case readBytes  = 5
    case writeBytes = 6
    case readKeyInfo = 9
}

private struct SMCParam {
    struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) = (
                0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private final class SMC {
    private let conn: io_connect_t
    init?() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iter) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iter) }
        let svc = IOIteratorNext(iter)
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &c) == kIOReturnSuccess else { return nil }
        self.conn = c
    }
    deinit { IOServiceClose(conn) }
    private func call(_ inp: inout SMCParam, _ out: inout SMCParam) -> kern_return_t {
        var sz = MemoryLayout<SMCParam>.stride
        return IOConnectCallStructMethod(conn, 2, &inp, MemoryLayout<SMCParam>.stride, &out, &sz)
    }
    private func fcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    func read(_ key: String) -> (ok: Bool, bytes: [UInt8], size: UInt32) {
        var inp = SMCParam(), out = SMCParam()
        inp.key = fcc(key); inp.data8 = SMCCmd.readKeyInfo.rawValue
        guard call(&inp, &out) == kIOReturnSuccess else { return (false, [], 0) }
        let sz = out.keyInfo.dataSize
        guard sz > 0 else { return (false, [], 0) }
        inp.keyInfo.dataSize = sz; inp.data8 = SMCCmd.readBytes.rawValue
        guard call(&inp, &out) == kIOReturnSuccess else { return (false, [], 0) }
        let b = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(sz))) }
        return (true, b, sz)
    }
    @discardableResult
    func write(_ key: String, bytes: [UInt8]) -> Bool {
        var inp = SMCParam(), out = SMCParam()
        inp.key = fcc(key); inp.data8 = SMCCmd.readKeyInfo.rawValue
        guard call(&inp, &out) == kIOReturnSuccess else { return false }
        inp.data8 = SMCCmd.writeBytes.rawValue
        inp.keyInfo.dataSize = out.keyInfo.dataSize
        var padded = bytes + Array(repeating: UInt8(0), count: max(0, 32 - bytes.count))
        if padded.count > 32 { padded = Array(padded.prefix(32)) }
        inp.bytes = (padded[0],padded[1],padded[2],padded[3],padded[4],padded[5],padded[6],padded[7],
                     padded[8],padded[9],padded[10],padded[11],padded[12],padded[13],padded[14],padded[15],
                     padded[16],padded[17],padded[18],padded[19],padded[20],padded[21],padded[22],padded[23],
                     padded[24],padded[25],padded[26],padded[27],padded[28],padded[29],padded[30],padded[31])
        guard call(&inp, &out) == kIOReturnSuccess else { return false }
        return out.result == 0
    }
    func hasKey(_ key: String) -> Bool {
        var inp = SMCParam(), out = SMCParam()
        inp.key = fcc(key); inp.data8 = SMCCmd.readKeyInfo.rawValue
        return call(&inp, &out) == kIOReturnSuccess && out.keyInfo.dataSize > 0
    }
}

private func toFloat(_ b: [UInt8], size: UInt32) -> Float {
    guard size >= 4, b.count >= 4 else { return 0 }
    var v: Float = 0; memcpy(&v, b, 4); return v
}
private func toBytes(_ v: Float) -> [UInt8] {
    var x = v; return withUnsafeBytes(of: &x) { Array($0) }
}

private final class FanControl {
    private let smc: SMC
    let count: Int
    private let minRPM: [Float]
    private let maxRPM: [Float]
    private let hasFtst: Bool
    private var unlocked = false

    init?(smc: SMC) {
        self.smc = smc
        let r = smc.read("FNum")
        let n = r.ok ? Int(r.bytes.first ?? 0) : 0
        guard n > 0 else { return nil }
        count = n
        minRPM = (0..<n).map { i in
            let r = smc.read(String(format: "F%dMn", i))
            return r.ok && r.size >= 4 ? toFloat(r.bytes, size: r.size) : 1200
        }
        maxRPM = (0..<n).map { i in
            let r = smc.read(String(format: "F%dMx", i))
            return r.ok && r.size >= 4 ? toFloat(r.bytes, size: r.size) : 6000
        }
        hasFtst = smc.hasKey("Ftst")
    }

    func setRPM(_ rpm: Float) {
        if hasFtst && !unlocked {
            smc.write("Ftst", bytes: [0x01])
            Thread.sleep(forTimeInterval: 0.6)
            unlocked = true
        }
        for i in 0..<count { smc.write(String(format: "F%dMd", i), bytes: [0x01]) }
        for i in 0..<count {
            let clamped = min(maxRPM.indices.contains(i) ? maxRPM[i] : 6000,
                              max(minRPM.indices.contains(i) ? minRPM[i] : 0, rpm))
            smc.write(String(format: "F%dTg", i), bytes: toBytes(clamped))
        }
    }

    func setAuto() {
        for i in 0..<count {
            smc.write(String(format: "F%dMd", i), bytes: [0x00])
            smc.write(String(format: "F%dTg", i), bytes: toBytes(0))
        }
        if hasFtst { smc.write("Ftst", bytes: [0x00]) }
        unlocked = false
    }

    func statusLine() -> String {
        let rpms = (0..<count).map { i -> String in
            let r = smc.read(String(format: "F%dAc", i))
            return "\(Int(r.ok && r.size >= 4 ? toFloat(r.bytes, size: r.size) : 0))"
        }.joined(separator: ",")
        return "ok fans=\(count) rpms=\(rpms)"
    }
}

guard let smc = SMC() else { fputs("error: SMC open failed\n", stderr); exit(1) }
guard let fans = FanControl(smc: smc) else { fputs("error: no fans\n", stderr); exit(1) }

let sockPath = "/tmp/boringnotch-thermal.sock"
var shouldStop = false
signal(SIGTERM) { _ in shouldStop = true }
signal(SIGINT)  { _ in shouldStop = true }
unlink(sockPath)

let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard serverFD >= 0 else { fputs("error: socket failed\n", stderr); exit(1) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: 104) { cptr in
        sockPath.withCString { strncpy(cptr, $0, 103) }
    }
}
let bindOk = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bindOk == 0 else { fputs("error: bind failed errno=\(errno)\n", stderr); exit(1) }
chmod(sockPath, 0o777)
listen(serverFD, 5)

func handle(_ fd: Int32) {
    var buf = [UInt8](repeating: 0, count: 512)
    let n = read(fd, &buf, 511)
    guard n > 0 else { return }
    let line = String(bytes: buf.prefix(Int(n)), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let parts = line.split(separator: " ", maxSplits: 1)
    let cmd = String(parts.first ?? "")
    let arg = parts.count > 1 ? String(parts[1]) : ""
    var resp = "ok"
    switch cmd {
    case "set":
        if let rpm = Float(arg), rpm >= 0 { fans.setRPM(rpm) }
        else { resp = "error: invalid rpm" }
    case "auto":
        fans.setAuto()
    case "status":
        resp = fans.statusLine()
    default:
        resp = "error: unknown command"
    }
    let out = Array((resp + "\n").utf8)
    write(fd, out, out.count)
}

while !shouldStop {
    let clientFD = accept(serverFD, nil, nil)
    if clientFD < 0 { if errno == EINTR { break }; continue }
    handle(clientFD)
    Darwin.close(clientFD)
}

fans.setAuto()
unlink(sockPath)
Darwin.close(serverFD)
SWIFTSRC

echo "Compiling daemon (this takes ~15 seconds)..."
mkdir -p "$INSTALL_DIR"
/usr/bin/xcrun swiftc "$TMP_SRC" -framework IOKit -O -target arm64-apple-macos13.0 -o "$DAEMON_DEST"
chmod 755 "$DAEMON_DEST"
chown root:wheel "$DAEMON_DEST"
rm -f "$TMP_SRC"

echo "Writing LaunchDaemon plist..."
cat > "$PLIST_DEST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DAEMON_DEST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/boringnotch-thermal.log</string>
</dict>
</plist>
EOF
chmod 644 "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"

echo "Loading daemon..."
# Stop any existing instance
launchctl bootout system "$PLIST_LABEL" 2>/dev/null || \
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
sleep 1

# Bootstrap is the correct API on macOS 13+; fall back to legacy load
if ! launchctl bootstrap system "$PLIST_DEST" 2>/dev/null; then
    launchctl load -w "$PLIST_DEST"
fi

# Give the daemon a moment to create the socket
sleep 2

if [ -S "/tmp/boringnotch-thermal.sock" ]; then
    echo "Done. Fan control daemon running (socket confirmed)."
else
    echo "Done. Daemon installed — socket not yet visible (may need a reboot or relogin)."
    echo "To check: sudo launchctl list com.boringnotch.thermaldaemon"
    echo "Logs:     cat /var/log/boringnotch-thermal.log"
fi
