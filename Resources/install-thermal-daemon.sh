#!/bin/bash
# install-thermal-daemon.sh
# Called via AppleScript "with administrator privileges" — runs as root.
# Compiles the fan control daemon from embedded source and installs it.

set -euo pipefail

INSTALL_DIR="/Library/BoringNotch"
DAEMON_DEST="$INSTALL_DIR/BoringNotchThermalDaemon"
PLIST_LABEL="com.boringnotch.thermaldaemon"
PLIST_DEST="/Library/LaunchDaemons/$PLIST_LABEL.plist"
TMP_SRC="/tmp/boringnotch_daemon_src.swift"

# ── Embedded daemon source ────────────────────────────────────────────────────
cat > "$TMP_SRC" << 'SWIFTSRC'
import Foundation
import IOKit

private enum SMCCmd: UInt8 {
    case readBytes = 5; case writeBytes = 6
    case getKeyFromIndex = 8; case readKeyInfo = 9
}

private struct SMCParam {
    struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers: (UInt8,UInt8,UInt8,UInt8,UInt16) = (0,0,0,0,0)
    var pLimit: (UInt16,UInt16,UInt32,UInt32,UInt32) = (0,0,0,0,0)
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0
    var data8: UInt8 = 0; var data32: UInt32 = 0
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
        let svc = IOIteratorNext(iter); guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &c) == kIOReturnSuccess else { return nil }
        self.conn = c
    }
    deinit { IOServiceClose(conn) }
    private func call(_ i: inout SMCParam, _ o: inout SMCParam) -> kern_return_t {
        var sz = MemoryLayout<SMCParam>.stride
        return IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<SMCParam>.stride, &o, &sz)
    }
    private func fcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    func read(_ key: String) -> (ok: Bool, bytes: [UInt8], size: UInt32) {
        var inp = SMCParam(), out = SMCParam()
        inp.key = fcc(key); inp.data8 = SMCCmd.readKeyInfo.rawValue
        guard call(&inp, &out) == kIOReturnSuccess else { return (false,[],0) }
        let sz = out.keyInfo.dataSize; guard sz > 0 else { return (false,[],0) }
        inp.keyInfo.dataSize = sz; inp.data8 = SMCCmd.readBytes.rawValue
        guard call(&inp, &out) == kIOReturnSuccess else { return (false,[],0) }
        return (true, withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(sz))) }, sz)
    }
    @discardableResult
    func write(_ key: String, bytes: [UInt8]) -> Bool {
        var inp = SMCParam(), out = SMCParam()
        inp.key = fcc(key); inp.data8 = SMCCmd.readKeyInfo.rawValue
        guard call(&inp, &out) == kIOReturnSuccess else { return false }
        inp.data8 = SMCCmd.writeBytes.rawValue; inp.keyInfo.dataSize = out.keyInfo.dataSize
        var p = bytes + Array(repeating: UInt8(0), count: max(0,32-bytes.count))
        if p.count > 32 { p = Array(p.prefix(32)) }
        inp.bytes = (p[0],p[1],p[2],p[3],p[4],p[5],p[6],p[7],p[8],p[9],p[10],p[11],p[12],p[13],p[14],p[15],
                     p[16],p[17],p[18],p[19],p[20],p[21],p[22],p[23],p[24],p[25],p[26],p[27],p[28],p[29],p[30],p[31])
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
private func toBytes(_ v: Float) -> [UInt8] { var x = v; return withUnsafeBytes(of: &x) { Array($0) } }

private final class FanControl {
    private let smc: SMC
    let count: Int
    private let minRPM: [Float]; private let maxRPM: [Float]
    private let hasFtst: Bool; private var unlocked = false
    init?(smc: SMC) {
        self.smc = smc
        let r = smc.read("FNum"); let n = r.ok ? Int(r.bytes.first ?? 0) : 0
        guard n > 0 else { return nil }; count = n
        minRPM = (0..<n).map { i in let r = smc.read(String(format:"F%dMn",i)); return r.ok&&r.size>=4 ? toFloat(r.bytes,size:r.size) : 1200 }
        maxRPM = (0..<n).map { i in let r = smc.read(String(format:"F%dMx",i)); return r.ok&&r.size>=4 ? toFloat(r.bytes,size:r.size) : 6000 }
        hasFtst = smc.hasKey("Ftst")
    }
    func setRPM(_ rpm: Float) {
        if hasFtst && !unlocked {
            smc.write("Ftst", bytes: [0x01]); Thread.sleep(forTimeInterval: 0.6); unlocked = true
        }
        for i in 0..<count { smc.write(String(format:"F%dMd",i), bytes: [0x01]) }
        for i in 0..<count {
            let lo = minRPM.indices.contains(i) ? minRPM[i] : 1200
            let hi = maxRPM.indices.contains(i) ? maxRPM[i] : 6000
            smc.write(String(format:"F%dTg",i), bytes: toBytes(min(hi, max(lo, rpm))))
        }
    }
    func setAuto() {
        for i in 0..<count {
            smc.write(String(format:"F%dMd",i), bytes: [0x00])
            smc.write(String(format:"F%dTg",i), bytes: toBytes(0))
        }
        if hasFtst { smc.write("Ftst", bytes: [0x00]) }; unlocked = false
    }
    func statusLine() -> String {
        let rpms = (0..<count).map { i -> String in
            let r = smc.read(String(format:"F%dAc",i))
            return "\(Int(r.ok&&r.size>=4 ? toFloat(r.bytes,size:r.size) : 0))"
        }.joined(separator:",")
        return "ok fans=\(count) rpms=\(rpms)"
    }
}

guard let smc = SMC() else { fputs("BoringNotchThermalDaemon: SMC open failed\n",stderr); exit(1) }
guard let fans = FanControl(smc: smc) else { fputs("BoringNotchThermalDaemon: no fans\n",stderr); exit(1) }

let sockPath = "/tmp/boringnotch-thermal.sock"
var lastCmd = "auto"; var shouldStop = false
signal(SIGTERM) { _ in shouldStop = true }; signal(SIGINT) { _ in shouldStop = true }
unlink(sockPath)
let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard serverFD >= 0 else { fputs("BoringNotchThermalDaemon: socket() failed\n",stderr); exit(1) }
var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: 104) { cptr in
        sockPath.withCString { strncpy(cptr, $0, 103) }
    }
}
let bindOk = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard bindOk == 0 else { fputs("BoringNotchThermalDaemon: bind() failed errno=\(errno)\n",stderr); exit(1) }
chmod(sockPath, 0o777); listen(serverFD, 5)

func handle(_ fd: Int32) {
    var buf = [UInt8](repeating:0, count:512)
    let n = read(fd, &buf, 511); guard n > 0 else { return }
    let line = String(bytes:buf.prefix(Int(n)),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
    let parts = line.split(separator:" ", maxSplits:1)
    let cmd = String(parts.first ?? ""); let arg = parts.count > 1 ? String(parts[1]) : ""
    var resp = "ok"
    switch cmd {
    case "set":
        if let rpm = Float(arg), rpm >= 0 { fans.setRPM(rpm); lastCmd = line }
        else { resp = "error: invalid rpm '\(arg)'" }
    case "auto": fans.setAuto(); lastCmd = "auto"
    case "status": resp = fans.statusLine()
    default: resp = "error: unknown '\(cmd)'"
    }
    let out = Array((resp+"\n").utf8); write(fd, out, out.count)
}

while !shouldStop {
    let clientFD = accept(serverFD, nil, nil)
    if clientFD < 0 { if errno == EINTR { break }; continue }
    handle(clientFD); Darwin.close(clientFD)
}
fans.setAuto(); unlink(sockPath); Darwin.close(serverFD)
SWIFTSRC
# ── End embedded source ───────────────────────────────────────────────────────

echo "Compiling fan control daemon (this takes ~10 seconds)..."

/usr/bin/xcrun swiftc \
    "$TMP_SRC" \
    -framework IOKit \
    -O \
    -target arm64-apple-macos13.0 \
    -o "/tmp/BoringNotchThermalDaemon" 2>&1

rm -f "$TMP_SRC"

mkdir -p "$INSTALL_DIR"
cp /tmp/BoringNotchThermalDaemon "$DAEMON_DEST"
rm -f /tmp/BoringNotchThermalDaemon
chmod 755 "$DAEMON_DEST"
chown root:wheel "$DAEMON_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null || true

cat > "$PLIST_DEST" << PLISTEOF
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
PLISTEOF

chmod 644 "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
launchctl load -w "$PLIST_DEST"

echo "Fan control daemon installed and started."
