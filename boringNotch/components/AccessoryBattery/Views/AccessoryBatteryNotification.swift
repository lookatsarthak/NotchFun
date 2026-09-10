//
//  AccessoryBatteryNotification.swift
//  boringNotch
//

import SwiftUI

/// The transient banner shown when you connect earbuds or headphones.
///
/// Transient, never permanent. The closed notch has two slots either side of the
/// hardware cut-out, they are added in pairs to keep the black centred, and the face and
/// the caffeine cup already contend for them — a third pair would take the resting notch
/// to roughly twice the width of the hardware and the expansion would stop reading as the
/// notch itself growing. When the notch is open there is room, and the reading lives in
/// the header beside the Mac's own battery instead.
struct AccessoryBatteryNotification: View {
    let accessory: AccessoryBattery
    let notchWidth: CGFloat

    var body: some View {
        NotchBannerRow(notchWidth: notchWidth) {
            Text(accessory.name)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        } trailing: {
            AccessoryBatteryGlyph(accessory: accessory)
        }
    }
}

/// A headphones icon and one number.
///
/// One number because `system_profiler` reports both earbuds identically even when only
/// one is in your ear, so a left/right split would be inventing a distinction the data
/// does not carry. See `AccessoryBattery`.
struct AccessoryBatteryGlyph: View {
    let accessory: AccessoryBattery
    var showsLabel: Bool = true

    /// Matches the thresholds the Mac's own battery glyph uses, so two batteries side by
    /// side in the header do not disagree about what counts as low.
    private var tint: Color {
        accessory.level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "airpods.gen3")
                .imageScale(.medium)
                .foregroundStyle(tint)
            if showsLabel {
                Text("\(accessory.level)%")
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessory.name) battery \(accessory.level) percent")
    }
}
