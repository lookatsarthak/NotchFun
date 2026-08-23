//
//  WebcamView.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//

import AVFoundation
import Defaults
import SwiftUI

struct CameraPreviewView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager: WebcamManager
    
    // Track if authorization request is in progress to avoid multiple requests
    @State private var isRequestingAuthorization: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewLayer = webcamManager.previewLayer {
                    CameraPreviewLayerView(previewLayer: previewLayer)
                        .scaleEffect(x: -1, y: 1)
                        .clipShape(
                            mirrorShape(
                                rectangleRadius: Defaults[.cornerRadiusScaling]
                                    ? MusicPlayerImageSizes.cornerRadiusInset.opened
                                    : MusicPlayerImageSizes.cornerRadiusInset.closed
                            )
                        )
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .opacity(webcamManager.isSessionRunning ? 1 : 0)
                }

                if !webcamManager.isSessionRunning {
                    ZStack {
                        placeholderBackground(size: geometry.size.width)
                        VStack(spacing: 8) {
                            Image(systemName: webcamManager.authorizationStatus == .denied ? "exclamationmark.triangle" : "web.camera")
                                .foregroundStyle(.gray)
                                .font(.system(size: geometry.size.width/3.5))
                            Text(webcamManager.authorizationStatus == .denied ? "Access Denied" : "Mirror")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .onTapGesture {
                handleCameraTap()
            }
            .onDisappear {
                webcamManager.stopSession()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    /// The round mirror stays a real circle rather than a rounded rectangle with a huge
    /// radius: a continuous corner clamped to half the side is a squircle, not a circle,
    /// so the shape has to switch where the radius used to.
    private func mirrorShape(rectangleRadius: CGFloat) -> AnyShape {
        Defaults[.mirrorShape] == .rectangle
            ? AnyShape(RoundedRectangle(cornerRadius: rectangleRadius, style: .continuous))
            : AnyShape(Circle())
    }

    @ViewBuilder
    private func placeholderBackground(size: CGFloat) -> some View {
        let fill = Color(red: 20/255, green: 20/255, blue: 20/255)
        if Defaults[.mirrorShape] == .rectangle {
            RoundedRectangle(
                cornerRadius: Defaults[.cornerRadiusScaling]
                    ? 12
                    : MusicPlayerImageSizes.cornerRadiusInset.closed,
                style: .continuous
            )
            .fill(fill)
            .strokeBorder(.white.opacity(0.04), lineWidth: 1)
            .frame(width: size, height: size)
        } else {
            Circle()
                .fill(fill)
                .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                .frame(width: size, height: size)
        }
    }

    private func handleCameraTap() {
        if isRequestingAuthorization {
            return // Prevent multiple authorization requests
        }
        
        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings to use the mirror feature."
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
            }
        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            // Reset the request flag after a reasonable delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isRequestingAuthorization = false
            }
        @unknown default:
            break
        }
    }
}

struct CameraPreviewLayerView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = nsView.bounds
        CATransaction.commit()
    }
}

#Preview {
    CameraPreviewView(webcamManager: .shared)
}
