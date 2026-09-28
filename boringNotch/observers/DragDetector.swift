//
//  DragDetector.swift
//  NotchFun
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import UniformTypeIdentifiers

final class DragDetector {

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?


    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false
    private var mouseDownLocation: CGPoint = .zero

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

    // MARK: - Private Helpers
    
    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        let validTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string
        ]
        return dragPasteboard.types?.contains(where: validTypes.contains) ?? false
    }

    /// Only the mouse-down monitor stays registered.
    ///
    /// All three used to be installed for the life of the app, once per display. The
    /// `leftMouseDragged` one fires for every pointer sample while any button is held —
    /// moving a window, selecting text, dragging a scrollbar, anywhere on the Mac, 60 to
    /// 120 times a second — and each of those did a pasteboard `changeCount` read, which
    /// is an IPC to the pasteboard server. None of that has anything to do with the notch.
    ///
    /// Now the expensive monitors exist only for the duration of a gesture, and a gesture
    /// that turns out not to be carrying content drops them immediately.
    func startMonitoring() {
        stopMonitoring()

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.mouseDownLocation = NSEvent.mouseLocation
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.beginGestureMonitors()
        }
    }

    /// Installed on mouse-down, torn down on mouse-up.
    private func beginGestureMonitors() {
        endGestureMonitors()

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self, self.isDragging else { return }

            if !self.isContentDragging {
                // The source app writes the drag pasteboard only once the pointer passes
                // its drag threshold, so give it a few points; past that, a gesture with
                // nothing on the pasteboard never will have, and is dropped. That keeps
                // a window move or a text selection to a handful of checks rather than
                // one per pointer sample. See DragGesturePolicy.
                switch DragGesturePolicy.decide(
                    pasteboardChanged: self.dragPasteboard.changeCount != self.pasteboardChangeCount,
                    from: self.mouseDownLocation,
                    to: NSEvent.mouseLocation
                ) {
                case .keepWatching:
                    return
                case .abandon:
                    self.endGestureMonitors(keepingMouseUp: true)
                    return
                case .content:
                    guard self.hasValidDragContent() else {
                        self.endGestureMonitors(keepingMouseUp: true)
                        return
                    }
                    self.isContentDragging = true
                }
            }

            let mouseLocation = NSEvent.mouseLocation
            self.onDragMove?(mouseLocation)

            let containsMouse = self.notchRegion.contains(mouseLocation)
            if containsMouse && !self.hasEnteredNotchRegion {
                self.hasEnteredNotchRegion = true
                self.onDragEntersNotchRegion?()
            } else if !containsMouse && self.hasEnteredNotchRegion {
                self.hasEnteredNotchRegion = false
                self.onDragExitsNotchRegion?()
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            self.isDragging = false
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.pasteboardChangeCount = -1
            self.endGestureMonitors()
        }
    }

    /// - Parameter keepingMouseUp: true when abandoning a gesture that is not carrying
    ///   content — the mouse-up monitor stays so the flags still get reset.
    private func endGestureMonitors(keepingMouseUp: Bool = false) {
        if let monitor = mouseDraggedMonitor { NSEvent.removeMonitor(monitor) }
        mouseDraggedMonitor = nil
        if !keepingMouseUp {
            if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
            mouseUpMonitor = nil
        }
    }

    func stopMonitoring() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }
}
