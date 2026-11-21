//
//  WebcamManager.swift
//  NotchFun
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//
import AVFoundation
import Defaults
import SwiftUI

@Observable
class WebcamManager: NSObject {
    static let shared = WebcamManager()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var captureSession: AVCaptureSession?
    var isSessionRunning: Bool = false
    
    var authorizationStatus: AVAuthorizationStatus = .notDetermined
    
    var cameraAvailable: Bool = false

    /// Between asking the camera to start and it running. The mirror button reads this so
    /// a click during warm-up closes the mirror instead of asking it to start again, and
    /// the preview shows a spinner rather than looking like nothing happened.
    var isStarting: Bool = false

    private let sessionQueue = DispatchQueue(label: "BoringNotch.WebcamManager.SessionQueue", qos: .userInitiated)
    
    private var isCleaningUp: Bool = false
    
    // MARK: - Constants
    
    // MARK: - Properties
    
    private override init() {
        super.init()
        // Read what macOS already knows. This used to stay .notDetermined until the first
        // click, which then only checked permission and never started the camera, so the
        // mirror needed a second click after every launch. Reading it does not prompt.
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasDisconnected), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasConnected), name: AVCaptureDevice.wasConnectedNotification, object: nil)
        checkCameraAvailability()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
        }
        captureSession = nil
            
        previewLayer = nil
    }

    // MARK: - Camera Management
    
    /// Checks current authorization status and requests access if needed
    func checkAndRequestVideoAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        switch status {
        case .authorized:
            checkCameraAvailability() // Check availability if authorized
        case .notDetermined:
            requestVideoAccess()
        case .denied, .restricted:
            NSLog("Camera access denied or restricted")
        @unknown default:
            NSLog("Unknown authorization status")
        }
    }
    
    /// Asks macOS for camera access if it has not asked yet, then reports the answer on
    /// the main thread, so a click that triggers the prompt can open the mirror once
    /// allowed instead of needing another click.
    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
                if granted { self?.checkCameraAvailability() }
                completion(granted)
            }
        }
    }

    /// Requests access to the camera
    private func requestVideoAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
                if granted {
                    self?.checkCameraAvailability() // Check availability if access granted
                }
            }
        }
    }
    
    /// Every camera the mirror could use, Continuity Camera included.
    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    /// The camera from Settings if it's connected, otherwise the built-in one. See `CameraChoice`.
    static func preferredCamera() -> AVCaptureDevice? {
        let devices = availableCameras()
        let cameras = devices.map { device in
            CameraChoice.Camera(id: device.uniqueID, kind: {
                switch device.deviceType {
                case .builtInWideAngleCamera: return .builtIn
                case .continuityCamera: return .continuity
                default: return .external
                }
            }())
        }
        guard let pick = CameraChoice.pick(from: cameras, chosen: Defaults[.mirrorCameraID]) else { return nil }
        return devices.first { $0.uniqueID == pick.id }
    }

    /// Settings picked another camera: rebuild the session on it, and keep it running if
    /// it was.
    func cameraChoiceChanged() {
        sessionQueue.async { [weak self] in
            guard let self, let session = self.captureSession else { return }
            let wasRunning = session.isRunning
            self.cleanupExistingSession()
            guard wasRunning else { return }
            self.setupCaptureSession { success in
                if success { self.startRunningCaptureSession() }
            }
        }
    }

    /// Checks if any camera devices are available and sets up capture session if needed
    func checkCameraAvailability() {
        let availableDevices = Self.availableCameras()
        
        let hasAvailableDevices = !availableDevices.isEmpty
        
        DispatchQueue.main.async {
            self.cameraAvailable = hasAvailableDevices
        }
    }
    
    /// Sets up the capture session with a completion handler
    private func setupCaptureSession(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { 
                completion(false)
                return 
            }
            
            // Clean up any existing session before creating a new one
            self.cleanupExistingSession()
            
            let session = AVCaptureSession()
            
            do {
                guard let videoDevice = Self.preferredCamera() else {
                    NSLog("No video devices available")
                    DispatchQueue.main.async {
                        self.isSessionRunning = false
                        self.isStarting = false
                        self.cameraAvailable = false
                    }
                    completion(false)
                    return
                }
                
                NSLog("Using camera: \(videoDevice.localizedName)")
                
                // Lock device for configuration
                try videoDevice.lockForConfiguration()
                defer { videoDevice.unlockForConfiguration() }
                
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                guard session.canAddInput(videoInput) else {
                    throw NSError(domain: "BoringNotch.WebcamManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
                }
                
                session.beginConfiguration()
                session.sessionPreset = .high
                session.addInput(videoInput)
                
                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.setSampleBufferDelegate(nil, queue: nil)
                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                }
                session.commitConfiguration()
                
                self.captureSession = session
                
                // Create and set up preview layer on main thread
                DispatchQueue.main.async {
                    self.cameraAvailable = true
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.videoGravity = .resizeAspectFill
                    self.previewLayer = previewLayer
                    
                    // Setup is complete, let the caller know
                    completion(true)
                }
                
                NSLog("Capture session setup completed successfully")
            } catch {
                NSLog("Failed to setup capture session: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    self.isStarting = false
                    self.cameraAvailable = false
                    self.previewLayer = nil
                }
                completion(false)
            }
        }
    }
    
    /// Cleans up an existing capture session, removing all inputs and outputs
    private func cleanupExistingSession() {
        if let existingSession = self.captureSession {
            // First stop the session if running
            if existingSession.isRunning {
                existingSession.stopRunning()
            }
            
            // Then perform configuration cleanup
            existingSession.beginConfiguration()
            
            // Remove all inputs and outputs
            for input in existingSession.inputs {
                existingSession.removeInput(input)
            }
            for output in existingSession.outputs {
                existingSession.removeOutput(output)
            }
            
            existingSession.commitConfiguration()
            self.captureSession = nil
            
            // Clear preview layer on main thread
            DispatchQueue.main.async {
                self.previewLayer = nil
            }
        }
    }

    @objc private func deviceWasDisconnected(notification: Notification) {
        NSLog("Camera device was disconnected")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.stopSession()
            DispatchQueue.main.async {
                self.cameraAvailable = false
            }
        }
    }

    @objc private func deviceWasConnected(notification: Notification) {
        NSLog("Camera device was connected")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.checkCameraAvailability()
        }
    }

    private func updateSessionState() {
        let isRunning = self.captureSession?.isRunning ?? false
        DispatchQueue.main.async {
            self.isSessionRunning = isRunning
            self.isStarting = false
        }
    }
    
    func startSession() {
        isStarting = true
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If no session exists, create new session
            if self.captureSession == nil {
                self.setupCaptureSession { success in
                    if success {
                        // Only start the session if setup was successful
                        self.startRunningCaptureSession()
                    }
                }
            } else {
                // Session already exists, just start it
                self.startRunningCaptureSession()
            }
        }
    }
    
    private func startRunningCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            // Always report back, even when there is nothing to start (already running,
            // or stopped while setting up), so isStarting never sticks.
            guard let session = self.captureSession, !session.isRunning else {
                self.updateSessionState()
                return
            }
            
            session.startRunning()
            
            // Update state on main thread
            self.updateSessionState()
            
            NSLog("Capture session started successfully")
        }
    }
    
    func stopSession() {
        isStarting = false
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Update state to indicate we're stopping
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
            
            self.cleanupExistingSession()
            
            NSLog("Capture session stopped and cleaned up")
        }
    }
}
