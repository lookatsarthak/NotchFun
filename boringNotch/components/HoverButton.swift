//
//  HoverButton.swift
//  boringNotch
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        
        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    // Deliberately not glass, unlike ClearConfirmButton.
                    //
                    // Every use of this button is inside MusicControlsView, which is
                    // wrapped in `.drawingGroup()` for the marquee and slider. That
                    // rasterizes the subtree into an offscreen buffer that starts
                    // transparent, so a backdrop-sampling effect has no backdrop to
                    // sample - and the window itself is `isOpaque = false` over a clear
                    // background, so the fallback backdrop is the desktop. Wallpaper
                    // appearing inside a capsule in the middle of the black notch is
                    // exactly the failure the whole design rule exists to prevent, and
                    // it cannot be ruled out by building. An opaque fill cannot fail
                    // that way.
                    Capsule()
                        .fill(isHovering ? Color.white.opacity(0.12) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(NotchMotion.control) {
                isHovering = hovering
            }
        }
    }
}
