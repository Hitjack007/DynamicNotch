//
//  ChargingSlotGlyph.swift
//  DynamicNotch
//
//  Small persistent charging indicator that takes over the disposable right
//  slot of an ambient live activity (Music/Download/AI Usage) while actively
//  charging, instead of the activity's normal content there.
//

import SwiftUI

struct ChargingSlotGlyph: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.green)
            .frame(width: size)
    }
}
