//
//  AppearanceSettings.swift
//  NotchFun
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import SwiftUI

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.mirrorCameraID) private var mirrorCameraID
    @Default(.sliderColor) var sliderColor

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Show the mirror")
                }
                    .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Picker("Mirror camera", selection: $mirrorCameraID) {
                    // Nil follows CameraChoice: the built-in camera, or the best one there is.
                    Text(WebcamManager.availableCameras().contains { $0.deviceType == .builtInWideAngleCamera } ? "Built-in" : "Automatic")
                        .tag(String?.none)
                    ForEach(WebcamManager.availableCameras().filter { $0.deviceType != .builtInWideAngleCamera }, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(String?.some(device.uniqueID))
                    }
                }
                .onChange(of: mirrorCameraID) { WebcamManager.shared.cameraChoiceChanged() }
                Defaults.Toggle(key: .mirrorFlipped) {
                    Text("Flip the picture, like a mirror")
                }
            } header: {
                Text("Mirror")
            }

            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show the face when nothing is playing")
                }
            } header: {
                Text("Face")
            }

            ClaudeCodeSection()
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Face & Mirror")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

/// Connect or disconnect Claude Code from the face. One button and the folder dialog; no
/// Terminal. See `ClaudeCodeConnection`.
struct ClaudeCodeSection: View {
    private let connection = ClaudeCodeConnection.shared

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code")
                    Text(connection.isConnected ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if connection.isConnected {
                    Button("Disconnect") { connection.disconnect() }
                } else {
                    Button("Connect…") { connection.connect() }
                }
            }
            if let problem = connection.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Claude Code on the face")
        } footer: {
            Text(
                "The face shows what Claude Code is doing: thinking while it works, looking up when it needs you, and smiling when it's done. Connecting adds a few hooks to Claude Code's settings in the ~/.claude folder; you'll be asked to choose that folder once. New and open sessions pick it up straight away, and Disconnect removes exactly what was added."
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }
}
