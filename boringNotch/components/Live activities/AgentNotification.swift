//
//  AgentNotification.swift
//  NotchFun
//

import SwiftUI

/// Claude Code's face beside the notch, for the moments that matter when the face itself
/// isn't on screen (music playing, for example): the face in its state on the left, and a
/// sign on the right. No words. The orange dot means it needs you; the check means a
/// session finished.
struct AgentNotification: View {
    let state: AgentBoard.State?
    let waitingCount: Int
    let notchWidth: CGFloat

    var body: some View {
        NotchBannerRow(notchWidth: notchWidth) {
            MinimalFaceFeatures()
        } trailing: {
            switch state {
            case .waiting:
                HStack(spacing: 3) {
                    // One dot per waiting session, up to three.
                    ForEach(0..<min(max(waitingCount, 1), 3), id: \.self) { _ in
                        Circle()
                            .fill(MinimalFaceFeatures.claudeOrange)
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.trailing, 6)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MinimalFaceFeatures.doneGreen)
                    .padding(.trailing, 6)
            default:
                EmptyView()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state == .done ? "Claude Code finished" : "Claude Code needs you")
    }
}
