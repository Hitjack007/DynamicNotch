//
//  sizeMatters.swift
//  DynamicNotch
//
//  Created by Mark Greene on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let openNotchSize: CGSize = .init(width: 640, height: 190)
let windowSize: CGSize = .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

/// The closed notch size for a screen, or nil when that screen can't be found right now
/// (for example while macOS is mid-way through a display wake or reconfiguration).
/// Callers that cache the result should keep their previous value on nil instead of
/// storing a made-up size.
@MainActor func resolvedClosedNotchSize(screenUUID: String? = nil) -> CGSize? {
    var notchHeight: CGFloat
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    guard let screen = selectedScreen else { return nil }

    // Calculate and set the exact width of the notch
    if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
       let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
    {
        notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
    }

    // Check if the Mac has a notch
    if screen.safeAreaInsets.top > 0 {
        // This is a display WITH a notch - use notch height settings
        notchHeight = Defaults[.notchHeight]
        if Defaults[.notchHeightMode] == .matchRealNotchSize {
            notchHeight = screen.safeAreaInsets.top
        } else if Defaults[.notchHeightMode] == .matchMenuBar {
            notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
        }
    } else {
        // This is a display WITHOUT a notch - use non-notch height settings
        notchHeight = Defaults[.nonNotchHeight]
        if Defaults[.nonNotchHeightMode] == .matchMenuBar {
            notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    resolvedClosedNotchSize(screenUUID: screenUUID)
        ?? .init(width: 185, height: Defaults[.nonNotchHeight])
}
