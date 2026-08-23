//
//  ClearConfirmButton.swift
//  boringNotch
//

import SwiftUI

/// A destructive "clear everything" control that asks once before doing it.
///
/// Shared by the clipboard tab and the shelf, which had grown near-identical copies of
/// this. Clearing either is unrecoverable, so a single click only arms it; the second
/// click within three seconds goes through.
///
/// The two states are one capsule that changes width rather than an icon being swapped
/// for a pill. Swapping meant SwiftUI had two unrelated views and nothing to interpolate,
/// so the control snapped between them. Here the capsule, its colour and both labels all
/// animate, and the confirm text is measured while invisible so the width has somewhere
/// to animate to.
struct ClearConfirmButton: View {
    /// How many things would be removed. Shown in the confirmation.
    let count: Int
    let idleHelp: String
    let confirmHelp: String
    let action: () -> Void

    @State private var confirming = false
    @State private var armedAt: Date?
    @State private var confirmWidth: CGFloat = 0

    private let idleDiameter: CGFloat = 26

    var body: some View {
        Button {
            // Always two clicks. There used to be an option-click that skipped the
            // confirmation, decided by reading NSEvent.modifierFlags - process-wide state
            // sampled outside an event context. That made a single click capable of
            // destroying data if the flags were ever read wrong, which is a bad trade for
            // saving one click on something unrecoverable.
            if confirming {
                action()
                confirming = false
                armedAt = nil
            } else {
                confirming = true
                armedAt = Date()
            }
        } label: {
            ZStack {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .opacity(confirming ? 0 : 1)
                    .scaleEffect(confirming ? 0.7 : 1)

                Text("Clear \(count)?")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .fixedSize()
                    .background(widthReader)
                    .opacity(confirming ? 1 : 0)
                    .scaleEffect(confirming ? 1 : 0.7)
            }
            .frame(
                width: confirming ? max(confirmWidth + 16, idleDiameter) : idleDiameter,
                height: idleDiameter
            )
            .background(
                Capsule().fill(
                    confirming ? Color.red.opacity(0.15) : Color.white.opacity(0.08)
                )
            )
            // Without this the confirm text spills out of the collapsed capsule while it
            // is still fading, since it stays in the layout to be measured.
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1)
        .help(confirming ? confirmHelp : idleHelp)
        .animation(.smooth(duration: 2.5), value: confirming)   // TEMP-DIAGNOSTIC
        .onChange(of: armedAt) { _, armed in
            guard let armed else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                // Only disarm if nothing re-armed it in the meantime.
                if armedAt == armed {
                    confirming = false
                    armedAt = nil
                }
            }
        }
        .onChange(of: count) { _, newCount in
            // Losing the last item while armed would leave a confirmation for nothing.
            if newCount == 0 { confirming = false; armedAt = nil }
        }
    }

    /// Reports the confirm label's natural width, so the capsule has a target to grow to.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .task(id: proxy.size.width) { confirmWidth = proxy.size.width }
        }
    }
}
