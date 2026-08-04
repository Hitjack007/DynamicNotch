//
//  AudioDeviceModel.swift
//  boringNotch
//

import Foundation

enum AudioDeviceModel {
    // Specific Apple models
    case airPods1
    case airPods2
    case airPods3
    case airPodsPro1
    case airPodsPro2Lightning
    case airPodsPro2USBC
    case airPodsMaxLightning
    case airPodsMaxUSBC
    case beatsStudioBuds
    case beatsFitPro
    case beatsStudioBudsPlus
    case beatsFlex
    case beatsSolo3
    case beatsStudio3
    case beatsPowerBeatsPro

    // Generic form-factor fallbacks (CoD-derived)
    case genericInEar    // Wearable Headset / Hands-free CoD minor class
    case genericOverEar  // Headphones CoD minor class
    case genericAudio    // Any other audio CoD or name fallback

    // Single property used by all rendering paths — no lookup table needed in views.
    var sfSymbolName: String {
        switch self {
        case .airPods1, .airPods2:
            return "airpods"
        case .airPods3:
            return "airpods.gen3"
        case .airPodsPro1, .airPodsPro2Lightning, .airPodsPro2USBC:
            return "airpodspro"
        case .airPodsMaxLightning, .airPodsMaxUSBC:
            return "airpodsmax"
        case .beatsStudioBuds, .beatsFitPro, .beatsStudioBudsPlus, .beatsFlex, .beatsPowerBeatsPro:
            return "earbuds"
        case .beatsSolo3, .beatsStudio3:
            return "headphones"
        case .genericInEar:
            return "airpodspro"
        case .genericOverEar:
            return "airpodsmax"
        case .genericAudio:
            return "headphones"
        }
    }

    // MARK: - Resolution

    // Priority 1: VID/PID exact match (Apple Bluetooth VID = 0x004C)
    private static let vidPidTable: [UInt32: AudioDeviceModel] = {
        func k(_ v: UInt16, _ p: UInt16) -> UInt32 { UInt32(v) << 16 | UInt32(p) }
        return [
            k(0x004C, 0x2002): .airPods1,
            k(0x004C, 0x200F): .airPods2,
            k(0x004C, 0x2061): .airPods3,
            k(0x004C, 0x200E): .airPodsPro1,
            k(0x004C, 0x2062): .airPodsPro2Lightning,
            k(0x004C, 0x2064): .airPodsPro2USBC,
            k(0x004C, 0x200A): .airPodsMaxLightning,
            k(0x004C, 0x2063): .airPodsMaxUSBC,
            k(0x004C, 0x2045): .beatsStudioBuds,
            k(0x004C, 0x2049): .beatsFitPro,
            k(0x004C, 0x2057): .beatsStudioBudsPlus,
            k(0x004C, 0x2060): .beatsFlex,
            k(0x004C, 0x200C): .beatsSolo3,
            k(0x004C, 0x200D): .beatsStudio3,
            k(0x004C, 0x200B): .beatsPowerBeatsPro,
        ]
    }()

    /// Resolve a Bluetooth audio device to its model using the three-tier priority chain.
    static func resolve(vendorID: UInt16, productID: UInt16, cod: UInt32, name: String) -> AudioDeviceModel {
        // Priority 1: VID/PID exact match
        if vendorID != 0 || productID != 0 {
            let key = UInt32(vendorID) << 16 | UInt32(productID)
            if let model = vidPidTable[key] { return model }
        }

        // Priority 2: CoD form-factor (major class 0x04 = Audio/Video)
        //   major = bits[12:8], minor = bits[7:2]
        let majorClass = (cod >> 8) & 0x1F
        if majorClass == 0x04 {
            let minorClass = (cod >> 2) & 0x3F
            switch minorClass {
            case 0x01, 0x02: return .genericInEar   // Wearable Headset, Hands-free
            case 0x06:       return .genericOverEar  // Headphones
            default:         return .genericAudio
            }
        }

        // Priority 3: Name substring (last resort — non-Apple devices without Audio CoD)
        let lower = name.lowercased()
        if lower.contains("airpods max") { return .airPodsMaxLightning }
        if lower.contains("airpods pro") { return .airPodsPro1 }
        if lower.contains("airpods")     { return .airPods2 }
        if lower.contains("beats") {
            if lower.contains("solo")                          { return .beatsSolo3 }
            if lower.contains("studio") && !lower.contains("bud") { return .beatsStudio3 }
            return .beatsStudioBuds
        }
        if lower.contains("headphone") || lower.contains("over-ear") || lower.contains("on-ear") {
            return .genericOverEar
        }
        if lower.contains("earbud") || lower.contains("in-ear") || lower.contains("bud") {
            return .genericInEar
        }
        return .genericAudio
    }
}
