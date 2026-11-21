//
//  NotchMessageNotification.swift
//  NotchFun
//

import SwiftUI

/// A Shortcuts or `notchfun://` message beside the closed notch: an optional symbol and
/// the text on the left, an optional progress ring on the right.
struct NotchMessageNotification: View {
    let message: NotchMessage
    let notchWidth: CGFloat

    /// Only symbols that exist; a made-up name draws nothing rather than a blank box.
    private var symbolExists: Bool {
        guard let symbol = message.symbol else { return false }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }

    var body: some View {
        NotchBannerRow(notchWidth: notchWidth) {
            HStack(spacing: 6) {
                if symbolExists, let symbol = message.symbol {
                    Image(systemName: symbol)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } trailing: {
            if let progress = message.progress {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
                .padding(.trailing, 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message.progress.map { "\(message.text), \(Int($0 * 100)) percent" } ?? message.text)
    }
}
