//
//  Color+AccentColor.swift
//  NotchFun
//
//  Created by Alexander on 2025-10-24.
//

import SwiftUI
import Defaults

extension Color {
    /// NotchFun's purple: the site's lavender, a step deeper so a white switch knob and
    /// white text on a selected row stay readable. The default accent everywhere, so
    /// Settings no longer looks like a different app from setup, the icon and the site.
    static let notchFunPurple = Color(nsColor: .notchFunPurple)

    static var effectiveAccent: Color {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return Color(nsColor: nsColor)
        }
        return .notchFunPurple
    }
    
    /// Returns a darker version of the accent color suitable for backgrounds
    static var effectiveAccentBackground: Color {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return Color(nsColor: nsColor.withSystemEffect(.disabled))
        }
        return Color.effectiveAccent.opacity(0.25)
    }
}

extension NSColor {
    static let notchFunPurple = NSColor(srgbRed: 0x8E / 255, green: 0x78 / 255, blue: 0xF2 / 255, alpha: 1)

    static var effectiveAccent: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return nsColor
        }
        return .notchFunPurple
    }
    
    /// Returns a darker version of the accent color as NSColor suitable for backgrounds
    static var effectiveAccentBackground: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return nsColor.withSystemEffect(.disabled)
        }
        return NSColor.notchFunPurple.withAlphaComponent(0.25)
    }
}
