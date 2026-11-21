//
//  SettingsWindowController.swift
//  NotchFun
//
//  Created by Alexander on 2025-06-14.
//

import AppKit
import SwiftUI
import Defaults
import Sparkle

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: SPUStandardUpdaterController?
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// For setup's "Update automatically" switch, which needs the same updater Settings uses.
    var updater: SPUUpdater? { updaterController?.updater }

    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        self.updaterController = controller
        // If Settings happens to be open already, rebuild it with the real updater.
        if window?.isVisible == true { installContent() }
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "NotchFun Settings"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("BoringNotchSettingsWindow")
        
        // The SwiftUI content is built on first show, not here: see `installContent`.

        // Handle window closing
        window.delegate = self
    }

    /// Builds the Settings view. Only while the window is open.
    ///
    /// It used to be built at launch and kept for good. A hidden NSHostingView still
    /// re-renders whenever anything it reads changes, and Settings reads a lot: every
    /// battery event while charging re-ran General, whose Launch at Login toggle asks the
    /// system for its status each time. That was most of NotchFun's idle CPU on a
    /// charging Mac, for a window nobody had opened.
    private func installContent() {
        window?.contentView = NSHostingView(rootView: SettingsView(updaterController: updaterController))
    }

    /// Frees the view once the window is gone, for the same reason.
    private func removeContent() {
        window?.contentView = NSView()
    }
    
    func showWindow() {
        if !(window?.contentView is NSHostingView<SettingsView>) { installContent() }

        // Set app to regular mode first
        NSApp.setActivationPolicy(.regular)
        
        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Show the window with proper ordering
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        
        // Activate the app and ensure window gets focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    override func close() {
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        window?.orderOut(nil)
        
        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
        // After the close has finished drawing, so the window doesn't flash empty.
        DispatchQueue.main.async { [weak self] in
            guard self?.window?.isVisible == false else { return }
            self?.removeContent()
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure app is in regular mode when window becomes key
        NSApp.setActivationPolicy(.regular)
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
}
