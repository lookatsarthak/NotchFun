import Foundation
import Cocoa
import AsyncXPCConnection

/// Talks to the XPC helper.
///
/// Isolated to the main actor as a whole, which is what it already was in practice: the
/// connection and the cached service were only ever created and cleared inside
/// `MainActor.run`, and every method hopped there to reach them. Saying so directly means
/// the service no longer has to be carried back out across an isolation boundary - it is
/// not `Sendable`, and moving it was what most of the concurrency warnings here were
/// about. `await` on these methods suspends rather than blocking, so an XPC round trip
/// still does not hold up the main thread.
@MainActor
final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()

    /// Explicitly nonisolated: `shared` is initialised lazily by whichever thread reaches
    /// it first, and every stored property here starts out nil or a constant, so there is
    /// nothing main-actor about constructing one.
    nonisolated override init() { super.init() }
    
    private let serviceName = "io.github.lookatsarthak.notchfun.XPCHelper"
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    /// `nonisolated(unsafe)` so `deinit` can cancel it. A `Task` handle is safe to cancel
    /// from any thread; deinit cannot hop to the main actor to do it.
    private nonisolated(unsafe) var monitoringTask: Task<Void, Never>?

    deinit {
        connection?.invalidate()
        monitoringTask?.cancel()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    private func ensureRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    private func getRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol>? {
        remoteService
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    func requestAccessibilityAuthorization() {
        Task {
            let service = ensureRemoteService()
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    /// Whether Accessibility is authorized, or `nil` when the helper could not be
    /// reached to find out.
    ///
    /// A failed XPC connection is not a denial, and collapsing the two is not harmless:
    /// it is how the HUD replacement setting used to switch itself off after an update.
    /// The first launch following an update is precisely when the helper is most likely
    /// to be briefly unreachable, because macOS is revalidating the bundle that Sparkle
    /// just replaced. Any caller that writes the answer to disk must handle `nil`.
    func accessibilityAuthorizationStatus() async -> Bool? {
        do {
            let service = ensureRemoteService()
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            notifyAuthorizationChange(result)
            return result
        } catch {
            return nil
        }
    }

    /// Convenience for callers that only need a yes/no and do nothing irreversible with
    /// it - showing a checkmark, or deciding whether to start the interceptor now.
    /// Anything that persists the answer should use `accessibilityAuthorizationStatus()`.
    func isAccessibilityAuthorized() async -> Bool {
        await accessibilityAuthorizationStatus() ?? false
    }
    
    /// Asks for Accessibility, prompting if requested. `nil` means the helper could not
    /// be reached, which is not the same as the user saying no - see
    /// `accessibilityAuthorizationStatus()`.
    func ensureAccessibilityAuthorizationStatus(promptIfNeeded: Bool) async -> Bool? {
        do {
            let service = ensureRemoteService()
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            notifyAuthorizationChange(result)
            return result
        } catch {
            return nil
        }
    }

    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        await ensureAccessibilityAuthorizationStatus(promptIfNeeded: promptIfNeeded) ?? false
    }
    
    // MARK: - Keyboard Brightness
    
    func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    func currentKeyboardBrightness() async -> Float? {
        do {
            let service = ensureRemoteService()
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    func currentScreenBrightness() async -> Float? {
        do {
            let service = ensureRemoteService()
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}


