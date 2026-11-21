//
//  CameraChoice.swift
//  NotchFun
//

import Foundation

/// Which camera the mirror uses.
///
/// The one picked in Settings if it's connected. Otherwise the Mac's built-in camera,
/// then any other plugged-in camera, and an iPhone's Continuity Camera only as a last
/// resort: macOS lists a nearby iPhone as a camera, and the mirror used to open on it by
/// surprise because it came first in the list.
enum CameraChoice {
    enum Kind: Sendable { case builtIn, external, continuity }

    struct Camera: Equatable, Sendable {
        let id: String
        let kind: Kind
    }

    static func pick(from cameras: [Camera], chosen: String?) -> Camera? {
        if let chosen, let match = cameras.first(where: { $0.id == chosen }) { return match }
        return cameras.first { $0.kind == .builtIn }
            ?? cameras.first { $0.kind == .external }
            ?? cameras.first
    }
}
