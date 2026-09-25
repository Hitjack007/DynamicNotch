//
//  SettingsNavigator.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2026-09-20.
//

import SwiftUI

/// Single source of truth for which Settings tab is selected, so callers outside
/// SettingsView (e.g. a What's New deep-link action) can jump to a specific tab.
@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    @Published var selectedTab = "General"

    private init() {}
}
