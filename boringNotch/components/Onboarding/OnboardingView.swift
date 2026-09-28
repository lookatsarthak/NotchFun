//
//  OnboardingView.swift
//  NotchFun
//

import Defaults
import SwiftUI

/// First-run setup: hello, pick features, the permissions those features need, a few
/// preferences, try the notch, done. OnboardingPlan decides which of those apply.
///
/// Settings apply as they are toggled, not at the end, because the real notch is right
/// there at the top of the screen and shows the effect - a better preview than any mock.
/// The one exception is the volume and brightness popup; see OnboardingChoices.
struct OnboardingView: View {
    @State private var step: OnboardingStep
    @State private var hudChoice: Bool
    @StateObject private var tryIt = OnboardingTryIt()

    @Default(.boringShelf) private var shelf
    @Default(.clipboardHistoryEnabled) private var clipboard
    @Default(.showCalendar) private var calendar
    @Default(.showMirror) private var mirror
    @Default(.openNotchOnHover) private var opensOnHover

    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    init(startAt: OnboardingStep, onFinish: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        _step = State(initialValue: startAt)
        _hudChoice = State(initialValue: Defaults[.hudReplacement])
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
    }

    private var choices: OnboardingChoices {
        OnboardingChoices(
            shelf: shelf,
            clipboardHistory: clipboard,
            calendar: calendar,
            mirror: mirror,
            mediaKeyHUD: hudChoice,
            opensOnHover: opensOnHover
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepContent
                    .id(step)
                    .transition(NotchMotion.transition(.opacity.combined(with: .offset(y: 8))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 40)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        // A fixed size. Steps differ in height, and resizing the window between them
        // would need animating to not jump; a fixed window never has to.
        .frame(width: 560, height: 620)
        .background(OnboardingBackground())
        .preferredColorScheme(.dark)
        .onChange(of: step) { _, newStep in
            Defaults[.onboardingResumeStep] = newStep.rawValue
        }
        .onAppear {
            Defaults[.onboardingResumeStep] = step.rawValue
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .hello:
            HelloStep()
        case .features:
            FeaturesStep(hudChoice: $hudChoice)
        case .permissions:
            PermissionsStep(
                permissions: OnboardingPlan.permissions(for: choices),
                wantsHUD: hudChoice,
                wantsClipboard: clipboard,
                onAccessibilityGranted: applyHUDChoice
            )
        case .preferences:
            PreferencesStep()
        case .tryIt:
            TryItStep(tasks: OnboardingPlan.tasks(for: choices), opensOnHover: opensOnHover, state: tryIt)
        case .done:
            DoneStep()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step == .hello {
                Button("Skip setup", action: finish)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            } else if let previous = OnboardingPlan.previous(before: step, choices: choices) {
                Button("Back") { go(to: previous) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }

            Spacer()
            progressDots
            Spacer()

            if step == .done {
                Button("Open Settings") {
                    finish()
                    onOpenSettings()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            Button(primaryTitle, action: advance)
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    private var progressDots: some View {
        let steps = OnboardingPlan.steps(for: choices)
        return HStack(spacing: 6) {
            ForEach(steps, id: \.self) { item in
                Capsule()
                    .fill(Color.white.opacity(item == step ? 0.9 : 0.25))
                    .frame(width: item == step ? 16 : 6, height: 6)
            }
        }
        .animation(NotchMotion.control, value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)")
    }

    private var primaryTitle: String {
        switch step {
        case .hello: return "Set up my notch"
        case .tryIt: return tryIt.isComplete(OnboardingPlan.tasks(for: choices)) ? "Continue" : "Skip"
        case .done: return "Done"
        default: return "Continue"
        }
    }

    // MARK: Navigation

    private func go(to next: OnboardingStep) {
        withAnimation(NotchMotion.page) { step = next }
    }

    private func advance() {
        if step == .hello {
            // Hovering does not open the notch while this is true (it keeps the hello
            // animation from being interrupted), and the steps after this one need it
            // to open: the live feature preview, and "Try it".
            BoringViewCoordinator.shared.firstLaunch = false
        }
        guard let next = OnboardingPlan.next(after: step, choices: choices) else {
            finish()
            return
        }
        go(to: next)
    }

    private func finish() {
        BoringViewCoordinator.shared.firstLaunch = false
        applyHUDChoice()
        tryIt.cleanUp()
        Defaults[.onboardingCompletedVersion] = OnboardingPlan.version
        Defaults[.onboardingResumeStep] = nil
        onFinish()
    }

    /// Writes the popup choice only when it can actually work. Switching the setting on
    /// without Accessibility would prompt again and switch itself back off.
    private func applyHUDChoice() {
        guard hudChoice != Defaults[.hudReplacement] else { return }
        if !hudChoice {
            Defaults[.hudReplacement] = false
            return
        }
        Task { @MainActor in
            if await XPCHelperClient.shared.accessibilityAuthorizationStatus() == true {
                Defaults[.hudReplacement] = true
            }
        }
    }
}

// MARK: - Shared pieces

/// The same night sky as the disk image window, so installing and setting up read as
/// one experience.
struct OnboardingBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0x07071A), Color(hex: 0x1B1446), Color(hex: 0x3A2878)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.75 : 1)))
            .contentShape(Capsule())
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.45 : 0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }
}

/// A tick that draws itself. Kept because it carries news: permissions are granted in
/// another app, System Settings, and this is how you see it worked when you come back.
/// Appears already drawn if the permission was granted before the step was shown.
struct DrawnCheckmark: View {
    let granted: Bool
    /// Draw in when first shown, rather than appearing complete. For a tick that
    /// replaces a button the moment something is granted; not for one that was already
    /// granted before the screen appeared, where there is no news to deliver.
    var drawsInOnAppear = false
    @State private var progress: CGFloat = 0

    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 16)
            .padding(6)
            // An empty ring until done, so an unfinished task reads as a checkbox
            // rather than a blank space.
            .background(Circle().fill(Color.green.opacity(progress > 0 ? 0.15 : 0)))
            .overlay(Circle().strokeBorder(Color.white.opacity(progress > 0 ? 0 : 0.3), lineWidth: 1.5))
            .onAppear {
                if drawsInOnAppear && granted && !NotchMotion.isReduced {
                    withAnimation(.easeOut(duration: 0.35)) { progress = 1 }
                } else {
                    progress = granted ? 1 : 0
                }
            }
            .onChange(of: granted) { _, now in
                withAnimation(NotchMotion.isReduced ? nil : .easeOut(duration: 0.35)) {
                    progress = now ? 1 : 0
                }
            }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY * 0.9))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return path
    }
}

/// A one-off burst of dots. Kept, once, for the file landing on the shelf: it confirms
/// the single thing the tutorial asked for. Runs for 0.7s when `trigger` changes and
/// costs nothing otherwise.
struct OnboardingBurst: View {
    let trigger: Int
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                let angle = Double(index) / 12 * 2 * .pi
                Circle()
                    .fill(index.isMultiple(of: 3) ? Color(hex: 0xB9A8FF) : .white)
                    .frame(width: 5, height: 5)
                    .offset(x: fired ? cos(angle) * 46 : 0, y: fired ? sin(angle) * 46 : 0)
                    .opacity(fired ? 0 : 1)
            }
        }
        .opacity(trigger == 0 || NotchMotion.isReduced ? 0 : 1)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            fired = false
            withAnimation(.easeOut(duration: 0.7)) { fired = true }
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
