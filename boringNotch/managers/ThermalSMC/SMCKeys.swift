//
//  SMCKeys.swift
//  boringNotch
//
//  SMC key constants and data conversion helpers for Apple Silicon.
//  Adapted from ThermalForge / agoodkind/macos-smc-fan (MIT).
//

import Foundation

// MARK: - Fan Keys

public enum SMCFanKey {
    /// Number of fans (uint8)
    public static let count = "FNum"

    // Templated keys — use key(_:fan:) to format with the zero-based fan index
    /// Actual RPM, read-only (flt)
    public static let actual = "F%dAc"
    /// Target RPM (flt)
    public static let target = "F%dTg"
    /// Minimum RPM (flt)
    public static let minimum = "F%dMn"
    /// Maximum RPM (flt)
    public static let maximum = "F%dMx"

    public static func key(_ template: String, fan: Int) -> String {
        String(format: template, fan)
    }
}

// MARK: - Data Conversion

/// Apple Silicon: IEEE 754 float, little-endian (4 bytes).
public func smcBytesToFloat(_ bytes: [UInt8], size: UInt32) -> Float {
    guard size >= 4, bytes.count >= 4 else { return 0 }
    var value: Float = 0
    memcpy(&value, bytes, 4)
    return value
}

/// Float → SMC bytes (IEEE 754 little-endian).
public func floatToSMCBytes(_ value: Float) -> [UInt8] {
    var v = value
    return withUnsafeBytes(of: &v) { Array($0) }
}

/// M5 GPU uses IOKit 16.16 fixed-point (ioft type, 8 bytes).
/// Upper 16 bits = integer part, lower 16 bits = fractional part.
public func ioftBytesToFloat(_ bytes: [UInt8]) -> Float {
    guard bytes.count >= 4 else { return 0 }
    var raw: UInt32 = 0
    memcpy(&raw, bytes, 4)
    let integer = Float(raw >> 16)
    let fraction = Float(raw & 0xFFFF) / 65536.0
    return integer + fraction
}
