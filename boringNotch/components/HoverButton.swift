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
                    // Glass only while hovered, so the control appears to lift off the
                    // notch rather than being cut into it. The notch surface underneath
                    // stays opaque black — see ClearConfirmButton for why that matters.
                    Capsule()
                        .fill(.clear)
                        .frame(width: size, height: size)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .opacity(isHovering ? 1 : 0)
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
