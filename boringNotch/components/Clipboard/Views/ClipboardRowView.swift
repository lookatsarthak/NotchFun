//
//  ClipboardRowView.swift
//  boringNotch
//

import SwiftUI

/// A single history row.
///
/// `Equatable` and applied with `.equatable()` so SwiftUI can skip re-rendering rows
/// that have not changed — the list lives inside a window that is on screen for the
/// entire life of the app, so cheap diffing matters more here than usual.
struct ClipboardRowView: View, Equatable {
    let item: ClipboardItem
    var highlightRanges: [Range<String.Index>] = []
    let shortcutLabel: String?
    let isSelected: Bool

    static let height: CGFloat = 26

    static func == (lhs: ClipboardRowView, rhs: ClipboardRowView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.title == rhs.item.title
            && lhs.item.pin == rhs.item.pin
            && lhs.shortcutLabel == rhs.shortcutLabel
            && lhs.isSelected == rhs.isSelected
            && lhs.highlightRanges == rhs.highlightRanges
    }

    var body: some View {
        HStack(spacing: 6) {
            shortcutBadge
                .frame(width: 26, alignment: .leading)

            leadingIcon
                .frame(width: 18, height: 18)

            Text(label)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let icon = ClipboardThumbnailService.shared.appIcon(forBundleID: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
                    .opacity(0.8)
            }

            Text(Self.relativeTime(from: item.lastCopiedAt))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.gray)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.effectiveAccent.opacity(0.65) : Color.clear)
        }
        .contentShape(Rectangle())
    }

    /// Emphasises the characters that matched the search query.
    private var label: AttributedString {
        let title = item.title.isEmpty ? "Image" : item.title
        guard !highlightRanges.isEmpty, !item.title.isEmpty else {
            return AttributedString(title)
        }
        return ClipboardSearchService.highlighted(title, ranges: highlightRanges)
    }

    @ViewBuilder
    private var shortcutBadge: some View {
        if let shortcutLabel {
            // lineLimit + fixedSize: the glyph is wide enough that without these the
            // label wraps onto a second line inside a 26pt row.
            Text(shortcutLabel)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .gray)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.12))
                }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if item.kind == .image,
           let thumbnail = ClipboardThumbnailService.shared.thumbnail(for: item, maxPixelSize: 20) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: item.isPinned ? "pin.fill" : item.kind.systemImage)
                .font(.system(size: 11))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isPinned ? Color.effectiveAccent : .gray)
        }
    }

    /// Compact age label — the row only has ~30pt for it.
    static func relativeTime(from date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3_600)h"
        case ..<604_800: return "\(seconds / 86_400)d"
        default: return "\(seconds / 604_800)w"
        }
    }
}
