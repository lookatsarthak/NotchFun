//
//  AccessoryPowerSources.swift
//  NotchFun
//

import Foundation
import IOKit.ps

/// The system's list of accessory batteries: what `pmset -g accps` prints.
///
/// AirPods and Beats report each bud and the case here, with charging state, straight
/// from their own Bluetooth broadcasts. It needs no permission and no helper process, and
/// it works inside the App Sandbox, unlike `system_profiler`.
///
/// The accessory list comes from `IOPSCopyPowerSourcesByType`, which IOKit exports but
/// doesn't declare in its public headers, so it is looked up at run time. If a future
/// macOS removes it, `read()` returns nil and the `system_profiler` path takes over.
enum AccessoryPowerSources {
    /// Posted by powerd when an accessory battery changes: a level, charging, or a case
    /// opening. It doesn't fire for the Mac's own battery, so listening costs nothing
    /// while no accessory is about.
    static let changeNotification = "com.apple.system.accpowersources.source"
    /// Posted when an accessory power source appears or goes away.
    static let attachNotification = "com.apple.system.accpowersources.attach"
    /// Posted when an accessory's time-remaining estimate moves, which tracks its level.
    static let timeRemainingNotification = "com.apple.system.accpowersources.timeremaining"
    /// All three. Measured over 15 minutes with AirPods in their case, they fired three
    /// times between them, against 26 for the Mac's own power notifications.
    static let notifications = [changeNotification, attachNotification, timeRemainingNotification]

    private typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    /// IOKit's private `kIOPSSourceForAccessories`.
    private static let accessorySources: Int32 = 4

    private static let copyByType: CopyByType? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType")
        else { return nil }
        return unsafeBitCast(symbol, to: CopyByType.self)
    }()

    /// One description per accessory power source, or nil if the list can't be read.
    static func read() -> [[String: Any]]? {
        guard let copyByType, let blob = copyByType(accessorySources)?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        return list.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }
    }
}
