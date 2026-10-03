//
//  AboutSettings.swift
//  NotchFun
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation(NotchMotion.page) {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    linkButton("Website", systemImage: "globe", url: URL(string: "https://lookatsarthak.github.io/NotchFun/"))
                    linkButton("Report a bug", systemImage: "ladybug", url: feedbackURL(kind: "bug"))
                    linkButton("Suggest", systemImage: "lightbulb", url: feedbackURL(kind: "idea"))
                    Button {
                        if let url = URL(string: "https://github.com/lookatsarthak/NotchFun") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("Made with 🫶🏻 by Sarthak · built on boring.notch by TheBoredTeam")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }

    /// The website's feedback form with the version and macOS already filled in, so a
    /// report from the app never arrives without them. No GitHub account needed, and the
    /// app itself sends nothing: it only opens the page in the browser.
    private func feedbackURL(kind: String) -> URL? {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var components = URLComponents(string: "https://lookatsarthak.github.io/NotchFun/feedback.html")
        components?.queryItems = [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "source", value: "app"),
            URLQueryItem(name: "version", value: "\(version) (\(build))"),
            URLQueryItem(name: "os", value: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
        ]
        return components?.url
    }

    private func linkButton(_ title: String, systemImage: String, url: URL?) -> some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .frame(height: 18)
                Text(title)
            }
            .contentShape(Rectangle())
        }
    }
}
