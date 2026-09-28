//
//  TabSelectionView.swift
//  NotchFun
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Clipboard", icon: "doc.on.clipboard.fill", view: .clipboard)
]

/// Tabs whose feature is currently switched on. Home is always present; the others
/// disappear entirely when their feature is disabled, so a user who never turns on
/// clipboard history never sees it.
@MainActor
func visibleTabs() -> [TabModel] {
    tabs.filter { tab in
        switch tab.view {
        case .home: return true
        case .shelf: return Defaults[.boringShelf]
        case .clipboard: return Defaults[.clipboardHistoryEnabled]
        }
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var shelfEnabled
    @Default(.clipboardHistoryEnabled) var clipboardEnabled
    @Namespace private var selection
    @State private var hovered: NotchViews?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs()) { tab in
                let selected = coordinator.currentView == tab.view
                TabButton(label: tab.label, icon: tab.icon, selected: selected) {
                    // No withAnimation here. A transaction animation overrides the
                    // timings a transition carries, which would force the outgoing tab
                    // to fade as slowly as the new one arrives - the two then smear
                    // together for several frames. The content transition brings its
                    // own timings, and the pill gets its own below.
                    coordinator.currentView = tab.view
                }
                .frame(height: 26)
                .foregroundStyle(.white.opacity(selected ? 1 : hovered == tab.view ? 0.75 : 0.45))
                .background {
                    // Exactly one pill, under the selected tab only, so matchedGeometryEffect
                    // has a single source and slides it to the next tab. This used to put a
                    // pill under *every* tab, hidden on all but one, all sharing one id -
                    // SwiftUI expects one source per id, so the slide was unreliable.
                    //
                    // The fill was secondarySystemFill, a translucent grey meant for
                    // window backgrounds, which on the always-black notch was barely
                    // visible. NotchHighlight explains why this is not Liquid Glass.
                    if selected {
                        Capsule()
                            .fill(NotchHighlight.fill)
                            .overlay(Capsule().strokeBorder(NotchHighlight.edge, lineWidth: 0.5))
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
                .onHover { inside in
                    withAnimation(NotchMotion.control) {
                        if inside { hovered = tab.view } else if hovered == tab.view { hovered = nil }
                    }
                }
                .help(tab.label)
            }
        }
        .animation(NotchMotion.content, value: coordinator.currentView)
    }
}

#Preview {
    BoringHeader().environment(BoringViewModel())
}
