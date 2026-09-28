//
//  BoringViewModel.swift
//  NotchFun
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

/// Main-actor isolated, explicitly.
///
/// It always was: it reads NSScreen, drives notch geometry and feeds SwiftUI. But the
/// isolation was being inferred from an `@ObservedObject` stored property - a wrapper
/// that does nothing outside a View - rather than stated. Removing that wrapper removed
/// the inference, so it is written down now.
///
/// @Observable, so each view redraws only for the properties it actually reads. As an
/// ObservableObject, any change - a hover flag, a drop-targeting flag, the AirDrop zone's
/// frame - redrew every one of the dozen-odd views observing it. Views get it through
/// `@Environment(BoringViewModel.self)`, injected with `.environment(_:)` wherever
/// `.environmentObject(_:)` used to be; a missing injection traps at runtime either way.
///
/// The views that observe it subscribe to their own settings with @Default. They used
/// to read `Defaults[...]` directly and only refreshed because some unrelated flag here
/// changed - which per-property tracking no longer does.
@MainActor
@Observable
class BoringViewModel: NSObject {
    let coordinator = BoringViewCoordinator.shared
    let detector = FullscreenMediaDetector.shared


    private(set) var notchState: NotchState = .closed

    var dragDetectorTargeting: Bool = false
    var generalDropTargeting: Bool = false
    var dropZoneTargeting: Bool = false
    var dropEvent: Bool = false

    /// Where the AirDrop zone sits, in the notch's drop coordinate space.
    ///
    /// The drop target covering the notch wins every drop inside it - the shelf's own
    /// targets are never consulted, whether that target is in front of them or behind.
    /// Rather than keep fighting SwiftUI over which view should win, it routes by
    /// location, and needs to know where the zones are to do that.
    var airDropZoneFrame: CGRect = .zero
    /// Hands providers to the AirDrop zone's own handler, which owns the NSView the
    /// share sheet has to be anchored to.
    @ObservationIgnored var airDropDropHandler: (([NSItemProvider]) -> Void)?

    @ObservationIgnored private var dropHighlightWatchdog: Task<Void, Never>?

    /// Lights the zone under the pointer, and arms a watchdog to put it out.
    ///
    /// The highlight cannot rely on being told the drag ended: a `dropUpdated` can
    /// arrive *after* `performDrop`, turning the zone back on with nothing left to turn
    /// it off, and the zone then stays lit until the app restarts. SwiftUI sends these
    /// updates about twenty times a second for as long as a drag is live, even a
    /// stationary one, so anything older than a few hundred milliseconds means the drag
    /// is over.
    func noteDropActivity(overAirDrop: Bool) {
        if dropZoneTargeting != overAirDrop { dropZoneTargeting = overAirDrop }
        if dragDetectorTargeting != !overAirDrop { dragDetectorTargeting = !overAirDrop }

        dropHighlightWatchdog?.cancel()
        dropHighlightWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.clearDropHighlight()
        }
    }

    func clearDropHighlight() {
        dropHighlightWatchdog?.cancel()
        dropHighlightWatchdog = nil
        if dropZoneTargeting { dropZoneTargeting = false }
        if dragDetectorTargeting { dragDetectorTargeting = false }
    }
    /// Computed, not stored.
    ///
    /// This was a stored property kept in sync by a CombineLatest3 over the three
    /// targeting flags below. It is simply their disjunction, so the pipeline and the
    /// duplicate state both go; each flag is observed, so a change still redraws.
    var anyDropZoneTargeting: Bool {
        dropZoneTargeting || dragDetectorTargeting || generalDropTargeting
    }
    /// `nonisolated(unsafe)` so `deinit` can tear them down. Unlike the singletons,
    /// these really are created and destroyed per screen. Cancelling a Task and
    /// removing a NotificationCenter observer are each safe from any thread.
    @ObservationIgnored private nonisolated(unsafe) var notificationObservers: [Any] = []
    @ObservationIgnored private nonisolated(unsafe) var settingTask: Task<Void, Never>?
    
    /// Whether the closed notch is suppressed for a fullscreen app.
    ///
    /// Starts false, deliberately. It used to start `true` and rely on an async
    /// pipeline to correct it - and that pipeline could not emit until `screenUUID`
    /// had been assigned, which happens well after init, so until then the notch's
    /// entire closed-state content was suppressed. If the assignment never happened
    /// there was no way back. Showing the notch briefly over a fullscreen app is a much
    /// smaller failure than hiding it indefinitely.
    private(set) var hideOnClosed: Bool = false

    var edgeAutoOpenActive: Bool = false
    var isHoveringCalendar: Bool = false
    /// Set while the pointer is over a vertically scrolling area inside the open notch.
    /// The pan-up-to-close gesture reads raw scroll-wheel events, so without this a
    /// scroll gesture inside such content is also read as "close the notch".
    var isHoveringScrollableContent: Bool = false
    var isBatteryPopoverActive: Bool = false

    var screenUUID: String? {
        didSet {
            guard oldValue != screenUUID else { return }
            Task { @MainActor [weak self] in self?.recomputeHideOnClosed() }
        }
    }

    var notchSize: CGSize = getClosedNotchSize()
    var closedNotchSize: CGSize = getClosedNotchSize()
    
    let webcamManager = WebcamManager.shared
    var isCameraExpanded: Bool = false
    var isRequestingAuthorization: Bool = false
    
    deinit {
        destroy()
    }

    nonisolated func destroy() {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        settingTask?.cancel()
        settingTask = nil
    }

    init(screenUUID: String? = nil) {
        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        setupDetectorObserver()
    }
    
    /// Recompute on change, rather than combining three publishers.
    ///
    /// This was a `CombineLatest3` over `$screenUUID`, the detector's published
    /// dictionary and a Defaults publisher. CombineLatest emits nothing until *every*
    /// input has produced a value, and `$screenUUID` produces nothing while the
    /// property is nil - which it is until `adjustWindowPosition` assigns it. So the
    /// notch sat on whatever `hideOnClosed` was initialised to for an unbounded time,
    /// and that initial value was `true`. Three plain reads, re-evaluated whenever any
    /// of them changes, has no ordering requirement and no unreachable state.
    private func setupDetectorObserver() {
        let fullscreenObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.fullscreenStatusChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recomputeHideOnClosed() }
        }
        notificationObservers.append(fullscreenObserver)

        settingTask = Task { @MainActor [weak self] in
            for await _ in Defaults.updates(.hideNotchOption, initial: false) {
                self?.recomputeHideOnClosed()
            }
        }

        Task { @MainActor [weak self] in self?.recomputeHideOnClosed() }
    }

    @MainActor
    private func recomputeHideOnClosed() {
        let enabled = Defaults[.hideNotchOption] != .never
        let isFullscreen = screenUUID.map { detector.fullscreenStatus[$0] ?? false } ?? false
        let shouldHide = enabled && isFullscreen
        guard shouldHide != hideOnClosed else { return }
        withAnimation(NotchMotion.shellClose) { hideOnClosed = shouldHide }
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
    
    func open() {
        self.notchSize = openNotchSize()
        self.notchState = .open
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()

        // Opening is a hover, so this is guarded by a 60s cache and an in-flight check;
        // sweeping the pointer across the notch must not spawn a subprocess per crossing.
        AccessoryBatteryManager.shared.refreshForNotchOpen()
    }

    /// - Parameter force: Bypasses `preventNotchClose`. An action the user took
    ///   deliberately — the toggle shortcut, picking a clipboard entry — must always
    ///   be able to close the notch, even while a feature is holding it open.
    func close(force: Bool = false) {
        // Do not close while a share picker or sharing service is active
        if !force && SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
    if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }

    func closeHello() {
        Task { @MainActor in
            // shellClose, not the library's open value: this collapses the notch, and
            // the open token carries bounce that reads as a glitch on the way out.
            withAnimation(NotchMotion.shellClose) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
