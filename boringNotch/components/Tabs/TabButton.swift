//
//  TabButton.swift
//  NotchFun
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            // Outline until selected, then filled: the pill says where you are and the
            // glyph agrees. One size and weight for every tab, lighter than the old
            // headline-sized symbols.
            Image(systemName: icon)
                .symbolVariant(selected ? .fill : .none)
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, 15)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
