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

/// An earbud icon labelling a battery glyph.
///
/// Deliberately the same `BatteryView` the Mac's own battery draws, at the same width.
/// The first version put the number beside the icon as plain text with a percent sign,
/// which put two differently-drawn readouts next to each other in the header — one set
/// inside a battery, one floating beside an icon — and the eye could not tell which
/// number belonged to which device. Same glyph for both, with the earbud saying which is
/// which, is easier to read in less space.
///
/// No percent sign, because the Mac battery does not use one and the glyph already says
/// it is a battery.
///
/// `BatteryView` rather than `BoringBatteryView`: that one is a button with a popover of
/// charge details, and there are none to show for an accessory. Like the caffeine cup,
/// this is status and must not be hoverable, or it competes with the gestures that own
/// the notch.
struct AccessoryBatteryGlyph: View {
    let accessory: AccessoryBattery
    /// Matches the Mac battery beside it. They must agree or the pair looks accidental.
    var batteryWidth: CGFloat = 30

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "airpods.gen3")
                .font(.system(size: batteryWidth * 0.42, weight: .medium))
                .foregroundStyle(.white)
            // Charging state is all false because it cannot be known: nothing in the
            // system_profiler payload says whether an accessory is charging, and showing
            // a bolt we cannot substantiate would be a lie. `batteryColor` still turns
            // the fill red under 20%, which is the part that matters.
            BatteryView(
                levelBattery: Float(accessory.level),
                isPluggedIn: false,
                isCharging: false,
                isInLowPowerMode: false,
                batteryWidth: batteryWidth,
                isForNotification: false
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessory.name) battery \(accessory.level) percent")
    }
}
