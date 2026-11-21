//
//  AudioOutputButton.swift
//  NotchFun
//

import AppKit
import CoreAudio
import SwiftUI

/// The "Output" control slot: a menu of everything that can play sound, the current one
/// ticked, and Sound Settings at the bottom.
///
/// A native menu rather than a popover. The music controls are drawn through
/// `.drawingGroup()`, which can't host a popover's anchor reliably, and a menu is what
/// macOS's own Sound menu uses, so it reads as the same control.
struct AudioOutputButton: View {
    var body: some View {
        HoverButton(icon: "airplayaudio", scale: .medium) {
            AudioOutputMenu.show()
        }
        .help("Output")
        .accessibilityLabel("Choose sound output")
    }
}

@MainActor
enum AudioOutputMenu {
    static func show() {
        let menu = NSMenu()
        let target = MenuTarget()
        menu.retainActionTarget(target)

        let current = SystemAudioOutput.deviceID()
        let devices = SystemAudioOutput.outputDevices()
        if devices.isEmpty {
            let empty = NSMenuItem(title: "No outputs found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = NSNumber(value: device.id)
            item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            item.state = device.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Sound Settings…", action: #selector(MenuTarget.openSettings), keyEquivalent: "")
        settings.target = target
        menu.addItem(settings)

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class MenuTarget: NSObject {
        @objc func choose(_ sender: NSMenuItem) {
            guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
            SystemAudioOutput.setOutput(AudioObjectID(id))
        }

        @objc func openSettings() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
