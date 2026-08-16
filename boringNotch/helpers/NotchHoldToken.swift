//
//  NotchHoldToken.swift
//  boringNotch
//

import Foundation

/// Keeps the notch open for as long as the token is alive.
///
/// `BoringViewModel.close()` already consults `SharingStateManager.preventNotchClose`
/// before touching any state, and every close path funnels through it — hover-out,
/// pan-up, the drop debounce, the battery popover, and the toggle shortcut's 3-second
/// auto-close. So a single refcount hold covers all of them without touching
/// `ContentView`.
///
/// Scoping this to an object rather than calling `beginInteraction()`/`endInteraction()`
/// by hand means an unbalanced call can't leave the notch stuck open: even if every
/// explicit release path is missed, `deinit` still gives the count back.
@MainActor
final class NotchHoldToken {
    /// Absolute ceiling on a hold. Nothing legitimate keeps the notch open this long,
    /// so if we ever get here something has gone wrong and the user gets their notch
    /// back regardless.
    static let maximumHold: Duration = .seconds(300)

    private var released = false
    private var ceilingTask: Task<Void, Never>?

    init(onForcedRelease: (@MainActor () -> Void)? = nil) {
        SharingStateManager.shared.beginInteraction()
        ceilingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.maximumHold)
            guard !Task.isCancelled, let self, !self.released else { return }
            self.release()
            onForcedRelease?()
        }
    }

    func release() {
        guard !released else { return }
        released = true
        ceilingTask?.cancel()
        ceilingTask = nil
        SharingStateManager.shared.endInteraction()
    }

    deinit {
        // deinit is nonisolated; hop to the main actor to balance the count.
        if !released {
            Task { @MainActor in
                SharingStateManager.shared.endInteraction()
            }
        }
    }
}
