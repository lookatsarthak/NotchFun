//
//  generic.swift
//  NotchFun
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case clipboard

    /// Left-to-right position in the tab bar, so a switch can animate the way it moved.
    var order: Int {
        switch self {
        case .home: return 0
        case .shelf: return 1
        case .clipboard: return 2
        }
    }
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
