//
//  generic.swift
//  boringNotch
//
//  Created by Mark Greene on 04/08/24.
//

import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case thermal
    case systemStats
    case aiUsage
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}

enum IdleNotchWidget: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case none        = "None"
    case batteryMac  = "Mac Battery"
    case bluetooth   = "Bluetooth"
    case nextEvent   = "Next Event"
    case temperature = "Temperature"
    case aiUsage     = "AI Usage"
    case time        = "Clock"

    var id: String { rawValue }
    var label: String { rawValue }

    var iconName: String {
        switch self {
        case .none:        return "xmark"
        case .batteryMac:  return "battery.100"
        case .bluetooth:   return "headphones"
        case .nextEvent:   return "calendar"
        case .temperature: return "thermometer.medium"
        case .aiUsage:     return "apple.intelligence"
        case .time:        return "clock"
        }
    }
}

/// One of the four closed-notch "ambient" activities that compete for the same slot.
/// Order among these is user-configurable via `Defaults[.ambientActivityOrder]`; see
/// `AmbientActivityResolver`.
enum AmbientActivity: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case music    = "Music"
    case download = "Download"
    case face     = "Face"
    case aiUsage  = "AI Usage"

    var id: String { rawValue }
    var label: String { rawValue }

    var iconName: String {
        switch self {
        case .music:    return "music.note"
        case .download: return "arrow.down.circle"
        case .face:     return "face.smiling"
        case .aiUsage:  return "apple.intelligence"
        }
    }
}
