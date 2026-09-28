//
//  BoringHeader.swift
//  NotchFun
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.boringShelf) private var boringShelf
    @Default(.caffeineButtonInNotch) private var caffeineButtonInNotch
    @Default(.clipboardHistoryEnabled) private var clipboardHistoryEnabled
    @Default(.settingsIconInNotch) private var settingsIconInNotch
    @Default(.showAccessoryBattery) private var showAccessoryBattery
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showMirror) private var showMirror
    @Default(.showOpenNotchHUD) private var showOpenNotchHUD
    let batteryModel = BatteryStatusViewModel.shared
    let accessoryBattery = AccessoryBatteryManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    /// The tab bar used to be gated purely on the Shelf. Any feature that owns a tab
    /// can now bring it on screen.
    private var shouldShowTabs: Bool {
        let shelfWantsTabs = boringShelf && (!tvm.isEmpty || coordinator.alwaysShowTabs)
        return shelfWantsTabs || clipboardHistoryEnabled
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if shouldShowTabs {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 8 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && showOpenNotchHUD {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(NotchMotion.transition(.scale(scale: 0.8).combined(with: .opacity)))
                    } else {
                        if caffeineButtonInNotch {
                            CaffeineButton()
                        }
                        if showMirror {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Image(systemName: "web.camera")
                                    .foregroundColor(.white)
                                    .imageScale(.medium)
                                    .notchHoverHighlight()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if settingsIconInNotch {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Image(systemName: "gear")
                                    .foregroundColor(.white)
                                    .imageScale(.medium)
                                    .notchHoverHighlight()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        // Before the Mac's own battery, so the two read left-to-right
                        // as "the thing you're wearing, then the thing you're using".
                        // Safe to add here: both header HStacks carry
                        // .frame(maxWidth: .infinity), so they split the remaining space
                        // and the black notch rectangle between them stays centred no
                        // matter what this side contains.
                        if showAccessoryBattery, let accessory = accessoryBattery.current {
                            AccessoryBatteryGlyph(accessory: accessory)
                        }
                        if showBatteryIndicator {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 8 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
