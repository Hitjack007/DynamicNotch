//
//  ThermalManager.swift
//  boringNotch
//

import Foundation
import Defaults
import SwiftUI

@MainActor
final class ThermalManager: ObservableObject {
    static let shared = ThermalManager()

    @Published var cpuTemp: Float = 0
    @Published var gpuTemp: Float = 0
    @Published var fanRPMs: [Float] = []
    @Published var isAvailable: Bool = false
    @Published var daemonAvailable: Bool = false
    var hasFans: Bool { fanCount > 0 }

    func detectHasFans() -> Bool {
        if isAvailable { return hasFans }
        guard let conn = SMCConnection() else { return false }
        let r = conn.readKey("FNum")
        return r.success ? (Int(r.bytes.first ?? 0) > 0) : false
    }

    private var smc: SMCConnection?
    private var timer: Timer?
    private var cpuKeys: [String] = []
    private var gpuKeys: [String] = []
    private var fanCount: Int = 0
    private var fanMin: [Float] = []
    private var fanMax: [Float] = []
    private var hasFtst: Bool = false

    // Direct-SMC fallback state (used when daemon isn't installed)
    private var fanUnlocked: Bool = false
    private var pendingFanFraction: Float? = nil

    private var lastAppliedFraction: Float = -1
    private var lastAlertDate: Date?

    private var sessionIsActive: Bool = true    // false during Fast User Switching
    private var screenIsUnlocked: Bool = true  // false while screen is locked
    private var canControlFans: Bool { sessionIsActive && screenIsUnlocked }

    private init() {
        if Defaults[.showThermalTab] {
            start()
        }
    }

    func start() {
        guard smc == nil else { return }
        guard let conn = SMCConnection() else {
            isAvailable = false
            return
        }
        smc = conn
        isAvailable = true
        buildKeyCache(conn)
        daemonAvailable = ThermalDaemonClient.shared.checkAvailability()

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleSessionResign() }
        }
        nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleSessionBecomeActive() }
        }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleScreenLock() }
        }
        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleScreenUnlock() }
        }
    }

    // MARK: - Session lifecycle

    private func handleSessionResign() {
        sessionIsActive = false
        resetToAuto()
    }

    private func handleSessionBecomeActive() {
        sessionIsActive = true
        lastAppliedFraction = -1
        tick()
    }

    private func handleScreenLock() {
        screenIsUnlocked = false
        resetToAuto()
    }

    private func handleScreenUnlock() {
        screenIsUnlocked = true
        lastAppliedFraction = -1
        tick()
    }

    func stop() {
        resetToAuto()  // hand fans back to Apple before disconnecting
        timer?.invalidate()
        timer = nil
        smc = nil
        isAvailable = false
        cpuTemp = 0
        gpuTemp = 0
        fanRPMs = []
        fanUnlocked = false
        lastAppliedFraction = -1
    }

    // MARK: - Fan Control (public)

    func resetToAuto() {
        pendingFanFraction = nil

        // Try daemon first
        if ThermalDaemonClient.shared.setAutoFan() {
            fanUnlocked = false
            lastAppliedFraction = -1
            daemonAvailable = true
            return
        }
        daemonAvailable = false

        // Direct SMC fallback
        guard let smc else { return }
        for i in 0..<fanCount {
            _ = smc.writeKey(SMCFanKey.key("F%dMd", fan: i), bytes: [0x00])
            _ = smc.writeKey(SMCFanKey.key(SMCFanKey.target, fan: i), bytes: floatToSMCBytes(0))
        }
        if hasFtst { _ = smc.writeKey("Ftst", bytes: [0x00]) }
        fanUnlocked = false
        lastAppliedFraction = -1
    }

    // MARK: - Fan Control (private)

    private func applyFraction(_ fraction: Float) {
        let lo = fanMin.first ?? 1200
        let hi = fanMax.first ?? 6000
        let targetRPM = lo + (hi - lo) * fraction

        // Daemon path — root process, writes always work
        if ThermalDaemonClient.shared.setFanRPM(targetRPM) {
            daemonAvailable = true
            return
        }
        daemonAvailable = false

        // Direct SMC fallback (M1 may silently ignore without root)
        guard let smc else { return }
        if hasFtst && !fanUnlocked {
            _ = smc.writeKey("Ftst", bytes: [0x01])
            pendingFanFraction = fraction
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, let f = self.pendingFanFraction else { return }
                self.pendingFanFraction = nil
                self.fanUnlocked = true
                self.writeFanTargetsDirect(fraction: f)
            }
            return
        }
        writeFanTargetsDirect(fraction: fraction)
    }

    private func writeFanTargetsDirect(fraction: Float) {
        guard let smc else { return }
        for i in 0..<fanCount {
            _ = smc.writeKey(SMCFanKey.key("F%dMd", fan: i), bytes: [0x01])
        }
        for i in 0..<fanCount {
            let lo = fanMin.indices.contains(i) ? fanMin[i] : 1200
            let hi = fanMax.indices.contains(i) ? fanMax[i] : 6000
            let staggered = lo + (hi - lo) * fraction + Float(i) * 115
            _ = smc.writeKey(SMCFanKey.key(SMCFanKey.target, fan: i), bytes: floatToSMCBytes(min(hi, max(lo, staggered))))
        }
    }

    // MARK: - Curve

    private func applyFanCurve() {
        guard Defaults[.fanCurveEnabled] else {
            if lastAppliedFraction >= 0 { resetToAuto() }
            return
        }
        let temp = max(cpuTemp, gpuTemp)
        let pts = Defaults[.fanCurvePoints].sorted { $0.tempC < $1.tempC }
        guard pts.count >= 2 else { return }

        let pct = evaluateCurve(pts, at: temp)
        let fraction = pct / 100.0

        guard abs(fraction - lastAppliedFraction) >= 0.02 else { return }
        lastAppliedFraction = fraction

        if fraction <= 0 {
            resetToAuto()
        } else {
            applyFraction(fraction)
        }
    }

    private func evaluateCurve(_ pts: [FanCurvePoint], at temp: Float) -> Float {
        guard let first = pts.first, let last = pts.last else { return 0 }
        if temp <= Float(first.tempC) { return Float(first.fanPercent) }
        if temp >= Float(last.tempC) { return Float(last.fanPercent) }
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            if temp >= Float(a.tempC) && temp <= Float(b.tempC) {
                let t = (temp - Float(a.tempC)) / Float(b.tempC - a.tempC)
                return Float(a.fanPercent) + t * Float(b.fanPercent - a.fanPercent)
            }
        }
        return Float(last.fanPercent)
    }

    // MARK: - Key cache / polling

    private func buildKeyCache(_ conn: SMCConnection) {
        let count = conn.getKeyCount()
        var cpu: [String] = []
        var gpu: [String] = []
        for i in 0..<count {
            guard let key = conn.getKeyAtIndex(i) else { continue }
            let prefix = String(key.prefix(2))
            switch prefix {
            case "TC", "Tp": cpu.append(key)
            case "TG", "Tg": gpu.append(key)
            default: break
            }
        }
        cpuKeys = cpu
        gpuKeys = gpu

        let fanResult = conn.readKey("FNum")
        fanCount = fanResult.success ? Int(fanResult.bytes.first ?? 0) : 0

        fanMin = (0..<fanCount).map { i in
            let r = conn.readKey(SMCFanKey.key(SMCFanKey.minimum, fan: i))
            return (r.success && r.size >= 4) ? smcBytesToFloat(r.bytes, size: r.size) : 1200
        }
        fanMax = (0..<fanCount).map { i in
            let r = conn.readKey(SMCFanKey.key(SMCFanKey.maximum, fan: i))
            return (r.success && r.size >= 4) ? smcBytesToFloat(r.bytes, size: r.size) : 6000
        }

        hasFtst = conn.getKeyInfo("Ftst") != nil
    }

    private func tick() {
        guard let smc else { return }
        cpuTemp = peakTemp(smc: smc, keys: cpuKeys)
        gpuTemp = peakTemp(smc: smc, keys: gpuKeys)
        fanRPMs = (0..<fanCount).compactMap { i in
            let r = smc.readKey(SMCFanKey.key(SMCFanKey.actual, fan: i))
            guard r.success else { return nil }
            let val = smcBytesToFloat(r.bytes, size: r.size)
            return val > 0 ? val : nil
        }
        guard canControlFans else { return }
        if Defaults[.fanCurvePreset] == .maxSpeed {
            if abs(1.0 - lastAppliedFraction) >= 0.02 {
                lastAppliedFraction = 1.0
                applyFraction(1.0)
            }
        } else {
            applyFanCurve()
        }
        checkThermalAlert()
    }

    private func peakTemp(smc: SMCConnection, keys: [String]) -> Float {
        var peak: Float = 0
        for key in keys {
            let r = smc.readKey(key)
            guard r.success else { continue }
            let val: Float = r.size == 8
                ? ioftBytesToFloat(r.bytes)
                : smcBytesToFloat(r.bytes, size: r.size)
            if val > 0 && val < 150 { peak = max(peak, val) }
        }
        return (peak * 10).rounded() / 10
    }

    private func checkThermalAlert() {
        guard Defaults[.thermalAlertEnabled] else { return }
        let threshold = Float(Defaults[.thermalAlertThreshold])
        let maxTemp = max(cpuTemp, gpuTemp)
        guard maxTemp >= threshold else { return }
        if let last = lastAlertDate, Date().timeIntervalSince(last) < 60 { return }
        lastAlertDate = Date()
        BoringViewCoordinator.shared.showThermalAlert(temp: maxTemp)
    }
}
