//
//  ClipboardKind.swift
//  boringNotch
//

import Foundation

/// Coarse classification of a clipboard entry, computed once at capture time so
/// the row view can pick an icon without touching any blob on disk.
enum ClipboardKind: String, Codable, Sendable {
    case text
    case link
    case image
    case files

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .files: return "doc"
        }
    }
}
