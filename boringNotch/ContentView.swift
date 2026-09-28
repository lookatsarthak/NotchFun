//
//  ContentView.swift
//  NotchFun
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(BoringViewModel.self) var vm
    @Default(.boringShelf) private var boringShelf
    /// Not read here directly: vm.chinHeight reads it, inside the model, where it is not
    /// tracked. Holding the subscription is what redraws the chin when it changes.
    @Default(.hideTitleBar) private var hideTitleBar
    @Default(.caffeineIndicatorInNotch) private var caffeineIndicatorInNotch
    @Default(.caffeineShowNotification) private var caffeineShowNotification
    @Default(.closeGestureEnabled) private var closeGestureEnabled
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.compactMusicLiveActivity) private var compactMusicLiveActivity
    @Default(.cornerRadiusScaling) private var cornerRadiusScaling
    @Default(.enableGestures) private var enableGestures
    @Default(.enableHaptics) private var enableHaptics
    @Default(.enableShadow) private var enableShadow
    @Default(.gestureSensitivity) private var gestureSensitivity
    @Default(.inlineHUD) private var inlineHUD
    @Default(.minimumHoverDuration) private var minimumHoverDuration
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.showAccessoryBattery) private var showAccessoryBattery
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.sneakPeekStyles) private var sneakPeekStyles
    let webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let caffeine = CaffeineManager.shared
    @Bindable var musicManager = MusicManager.shared
    let batteryModel = BatteryStatusViewModel.shared
    let accessoryBattery = AccessoryBatteryManager.shared
    let brightnessManager = BrightnessManager.shared
    let volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace
    @Namespace private var caffeineNamespace


    @Default(.showNotHumanFace) var showNotHumanFace

    private let animationSpring = NotchMotion.drag

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && cornerRadiusScaling)
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && cornerRadiusScaling)
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    /// Whether the closed notch is currently showing the caffeine cup.
    ///
    /// The single source of truth for both the width below and the view body. Restating
    /// these conditions in two places is how the notch ends up wide with an empty slot.
    private var showsCaffeineIndicator: Bool {
        CaffeineIndicatorPolicy.showsIndicator(
            .init(
                isActive: caffeine.isActive,
                settingEnabled: caffeineIndicatorInNotch,
                notchIsClosed: vm.notchState == .closed,
                hiddenForFullscreen: vm.hideOnClosed,
                bannerIsShowing: coordinator.expandingView.show,
                inlineHUDIsShowing: coordinator.sneakPeek.show && inlineHUD
                    && coordinator.sneakPeek.type != .music
                    && coordinator.sneakPeek.type != .battery
            )
        )
    }

    /// Wide enough for any banner row, which is a different thing from the open notch's
    /// width even though both happen to be 640. Naming it stops the two being conflated:
    /// a banner's hover area has no business changing because the open notch was resized.
    private static let bannerChinWidth: CGFloat = 640

    /// Whether the closed notch is currently showing the Mac's own power banner.
    private var showsPowerBanner: Bool {
        coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && showPowerStatusNotifications
    }

    private var showsAccessoryBatteryBanner: Bool {
        AccessoryBatteryPolicy.showsBanner(
            .init(
                hasReading: accessoryBattery.current != nil,
                settingEnabled: showAccessoryBattery,
                bannerRequested: coordinator.expandingView.show
                    && coordinator.expandingView.type == .accessoryBattery,
                notchIsClosed: vm.notchState == .closed,
                hiddenForFullscreen: vm.hideOnClosed,
                powerBannerIsShowing: showsPowerBanner,
                inlineHUDIsShowing: coordinator.sneakPeek.show && inlineHUD
                    && coordinator.sneakPeek.type != .music
                    && coordinator.sneakPeek.type != .battery
            )
        )
    }

    private var showsCaffeineBanner: Bool {
        coordinator.expandingView.type == .caffeine && coordinator.expandingView.show
            && vm.notchState == .closed && caffeineShowNotification
    }

    /// Any full-width banner row. All three need the same wide hover chin.
    ///
    /// The caffeine banner was missing from the width calculation entirely: it draws a
    /// row around 354pt wide while the chin stayed at the bare notch width, because none
    /// of the branches below matched it. Only visible with `hideTitleBar` on, which is
    /// presumably why nobody reported it.
    private var showsAnyBanner: Bool {
        showsPowerBanner || showsAccessoryBatteryBanner || showsCaffeineBanner
    }

    /// One square slot beside the physical notch, the same size the face and album art use.
    private var notchSlotSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    /// The music row's own slot sizes. Deliberately separate from `notchSlotSize`: the
    /// face and the caffeine cup keep the standard slot, and only the music row is
    /// compactable. Read by both the view body and `computedChinWidth` so the invisible
    /// hover chin cannot drift from the visible row.
    private var musicMetrics: MusicLiveActivityMetrics.Metrics {
        MusicLiveActivityMetrics.metrics(
            .init(
                closedNotchHeight: vm.effectiveClosedNotchHeight,
                compact: compactMusicLiveActivity,
                gestureProgress: gestureProgress
            )
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if showsAnyBanner {
            chinWidth = Self.bannerChinWidth
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += musicMetrics.addedWidth
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && showNotHumanFace
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
            // The face already reserves an empty slot on the left, so the cup goes there
            // for free - no width change when caffeine turns on while idle.
            return chinWidth
        }

        if showsCaffeineIndicator {
            // Twice, not once: the cup on the left is matched by an empty slot on the
            // right so the notch cut-out stays centred under the hardware.
            chinWidth += 2 * (notchSlotSize + 10)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? cornerRadiusScaling
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && enableShadow)
                            ? .black.opacity(0.7) : .clear, radius: cornerRadiusScaling ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    // Opening overshoots slightly and closing settles flat. The asymmetry
                    // is the point: the shell should feel physical on the way out and
                    // decisive on the way back.
                    .animation(vm.notchState == .open ? NotchMotion.shellOpen : NotchMotion.shellClose,
                               value: vm.notchState)
                    .animation(NotchMotion.drag, value: gestureProgress)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(enableGestures) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(closeGestureEnabled && enableGestures) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation(NotchMotion.content) {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize().width, maxHeight: windowSize().height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(NotchMotion.drag, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environment(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if showsPowerBanner {
                        NotchBannerRow(notchWidth: vm.closedNotchSize.width) {
                            Text(batteryModel.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        } trailing: {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                isForNotification: true
                            )
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      // A key the user just pressed outranks a caffeine banner. Battery stays
                      // above both: it reports a power change nothing else announces.
                      } else if coordinator.sneakPeek.show && inlineHUD && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      // Below the HUD deliberately: you connect earbuds and reach for the
                      // volume keys a second later, and winning here would eat that feedback.
                      } else if showsAccessoryBatteryBanner, let accessory = accessoryBattery.current {
                          AccessoryBatteryNotification(
                              accessory: accessory,
                              notchWidth: vm.closedNotchSize.width
                          )
                          .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                          .transition(NotchMotion.transition(.opacity.combined(with: .scale)))
                      } else if showsCaffeineBanner {
                          CaffeineNotification(
                              isActive: caffeine.isActive,
                              detail: caffeine.session?.duration.shortTitle,
                              notchWidth: vm.closedNotchSize.width,
                              namespace: caffeineNamespace
                          )
                          .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          HStack(spacing: 0) {
                              // Music owns both slots, so the cup gets its own on the far left.
                              //
                              // The empty slot on the right is not decoration. MusicLiveActivity
                              // is [artwork][black rectangle][visualizer], and that black
                              // rectangle is what covers the physical notch - it only stays
                              // over the hardware because the artwork and the visualizer either
                              // side of it are the same width. Adding the cup to one side alone
                              // slid the whole row across and put the artwork over the notch.
                              if showsCaffeineIndicator {
                                  CaffeineNotchIndicator(size: notchSlotSize, namespace: caffeineNamespace)
                                      .padding(.trailing, 10)
                                      .transition(NotchMotion.transition(.opacity.combined(with: .scale)))
                              }
                              MusicLiveActivity()
                              if showsCaffeineIndicator {
                                  Color.clear
                                      .frame(width: notchSlotSize + 10, height: notchSlotSize)
                              }
                          }
                          .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && showNotHumanFace && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                      } else if showsCaffeineIndicator {
                          // Nothing else is claiming the closed notch - the face is off and
                          // no music is playing - so the cup stands on its own.
                          HStack(spacing: 0) {
                              CaffeineNotchIndicator(size: notchSlotSize, namespace: caffeineNamespace)
                                  .padding(.trailing, 10)
                              Rectangle()
                                  .fill(.black)
                                  .frame(width: vm.closedNotchSize.width - 20)
                              // Balances the cup, so the black area stays over the notch.
                              Color.clear
                                  .frame(width: notchSlotSize + 10, height: notchSlotSize)
                          }
                          .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                          .transition(.opacity)
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !inlineHUD && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && sneakPeekStyles == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: playerColorTinting ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && sneakPeekStyles == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    // Each branch carries the same transition so every tab animates
                    // identically. The transition on the enclosing VStack below is a
                    // different thing entirely — it fires when the notch itself opens
                    // and closes, not when the tab changes.
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                            .transition(.notchTab(direction: coordinator.tabDirection))
                    case .shelf:
                        ShelfView()
                            .transition(.notchTab(direction: coordinator.tabDirection))
                    case .clipboard:
                        ClipboardView()
                            .transition(.notchTab(direction: coordinator.tabDirection))
                    }
                }
                // The container leads, the content follows.
                //
                // This is what makes the notch read as one object growing rather than a
                // box with things appearing inside it. Opening, the shell starts moving
                // first and the content arrives a beat behind it. Closing, the content
                // goes first and the shell follows it down - so the notch is never seen
                // shrinking around content that is still there.
                //
                // Both halves finish inside the shell's own window: insertion runs
                // 60-340ms against a 420ms open, removal is done at 200ms against a 450ms
                // close.
                .transition(
                    .asymmetric(
                        insertion: NotchMotion.transition(
                            .scale(scale: 0.8, anchor: .top).combined(with: .opacity)
                        )
                        .animation(NotchMotion.content.delay(NotchMotion.contentLead)),
                        removal: .opacity.animation(NotchMotion.control)
                    )
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        // Behind the content, deliberately.
        //
        // As a normal modifier this sits in front and wins every drop in the notch,
        // which is what stopped the shelf's own targets from ever running. Accepting the
        // drop here instead of cancelling it fixed dropping onto the notch, but it also
        // meant the AirDrop zone never saw a drop and neither zone lit up, because their
        // isTargeted bindings belong to targets that were no longer being consulted.
        //
        // In `.background` it only receives what nothing in front of it claimed: drop on
        // AirDrop and FileShareView handles it, drop on the shelf and ShelfView does,
        // drop anywhere else on the notch and this catches it.
        .coordinateSpace(name: NotchDropSpace.name)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onDrop(
                    of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                    delegate: GeneralDropTargetDelegate(isTargeted: Bindable(vm).generalDropTargeting, vm: vm)
                )
        }
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                // This slot is otherwise empty, so the cup costs no extra notch width here.
                if showsCaffeineIndicator {
                    CaffeineNotchIndicator(size: notchSlotSize, namespace: caffeineNamespace)
                } else {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: notchSlotSize, height: notchSlotSize)
                }
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        // Explicit spacing, not SwiftUI's default. `computedChinWidth` has to know this
        // number to size the hover chin, and it used to guess it as a bare `+ 20`.
        HStack(spacing: musicMetrics.spacing) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                        style: .continuous)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: musicMetrics.artSize,
                    height: musicMetrics.artSize
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: coloredSpectrogram
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && sneakPeekStyles == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    coloredSpectrogram
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && sneakPeekStyles == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && sneakPeekStyles == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                Rectangle()
                    .fill(
                        coloredSpectrogram
                            ? Color(nsColor: musicManager.avgColor).gradient
                            : Color.gray.gradient
                    )
                    .frame(width: 50, alignment: .center)
                    .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                    .mask {
                        AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                            .frame(width: 16, height: 12)
                    }
            }
            .frame(
                width: musicMetrics.spectrumWidth,
                height: musicMetrics.spectrumHeight,
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if boringShelf && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: nil) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && enableHaptics {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  openNotchOnHover else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(minimumHoverDuration))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / gestureSensitivity) * 20
        }

        if translation > gestureSensitivity {
            if enableHaptics {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open, !vm.isHoveringCalendar, !vm.isHoveringScrollableContent else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / gestureSensitivity) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > gestureSensitivity {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if enableHaptics {
                haptics.toggle()
            }
        }
    }
}


/// The drop target covering the whole notch.
///
/// This sits on the outermost container, and in this layout it wins the drop over the
/// shelf's own targets inside it. It used to answer `dropUpdated` with `.cancel` and
/// `performDrop` with `false`, so a file dragged onto the notch lit up the drop zones
/// and was then refused: the shelf's handler never ran, nothing was recorded, and the
/// file simply did not arrive. Dragging onto an already-open shelf worked, which is why
/// it looked intermittent rather than broken.
///
/// It now accepts and hands the items to the shelf, so a drop anywhere on the notch
/// lands. When the shelf is switched off it still cancels, which is what should happen.
/// The coordinate space drop locations and zone frames are both measured in.
enum NotchDropSpace {
    static let name = "notchDropSpace"
}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let vm: BoringViewModel

    private static let acceptedTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText, .data]

    private func isOverAirDrop(_ info: DropInfo) -> Bool {
        let frame = vm.airDropZoneFrame
        return frame != .zero && frame.contains(info.location)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        vm.clearDropHighlight()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard Defaults[.boringShelf] else { return DropProposal(operation: .cancel) }
        // Light up whichever zone the pointer is actually over. These are the same
        // flags the zones' own targets would set, and the zones already draw their
        // border from them - they simply never got set once this target started
        // winning the drop.
        vm.noteDropActivity(overAirDrop: isOverAirDrop(info))
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        vm.clearDropHighlight()
        guard Defaults[.boringShelf] else { return false }

        let providers = info.itemProviders(for: Self.acceptedTypes)
        guard !providers.isEmpty else { return false }

        vm.dropEvent = true
        if isOverAirDrop(info), let share = vm.airDropDropHandler {
            share(providers)
        } else {
            ShelfStateViewModel.shared.load(providers)
        }

        return true
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environment(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
