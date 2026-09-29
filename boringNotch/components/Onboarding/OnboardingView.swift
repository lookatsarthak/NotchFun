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
    @State private var helloShown = false

    @Default(.boringShelf) private var shelf
    @Default(.clipboardHistoryEnabled) private var clipboard
    @Default(.showCalendar) private var calendar
    @Default(.showMirror) private var mirror
    @Default(.openNotchOnHover) private var opensOnHover

    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    init(startAt: OnboardingStep, onFinish: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        _step = State(initialValue: startAt)
        _hudChoice = State(initialValue: Defaults[.onboardingPendingHUDChoice] ?? Defaults[.hudReplacement])
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
        // Kept until setup finishes, so quitting partway and coming back remembers it.
        .onChange(of: hudChoice) { _, choice in
            Defaults[.onboardingPendingHUDChoice] = choice
        }
        .onAppear {
            Defaults[.onboardingResumeStep] = step.rawValue
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .hello:
            HelloStep(firstShow: !helloShown) { helloShown = true }
                .modifier(HeroPlacement())
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
                .modifier(HeroPlacement())
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
            if step == .tryIt && !tryIt.isComplete(OnboardingPlan.tasks(for: choices)) {
                // Not the white button: skipping is allowed, not what the screen is for.
                // It becomes the white Continue once every task is ticked.
                Button("Skip", action: advance)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(primaryTitle, action: advance)
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
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
        Defaults[.onboardingPendingHUDChoice] = nil
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

/// Hello and Done are short. Centred, slightly above the middle, rather than leaving
/// the bottom half of the window empty; the task steps stay top-aligned so their
/// titles line up with each other.
private struct HeroPlacement: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Buttons answer the pointer before the click, as native ones do. A style cannot hold
/// state itself, so each one draws through this.
private struct HoverAware<Content: View>: View {
    @ViewBuilder let content: (_ hovering: Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering)
            .onHover { hovering = $0 }
            .animation(NotchMotion.control, value: hovering)
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverAware { hovering in
            configuration.label
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.75 : 1)))
                .shadow(color: .white.opacity(hovering ? 0.25 : 0), radius: 8)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
        }
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverAware { hovering in
            configuration.label
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(configuration.isPressed ? 0.45 : (hovering ? 0.95 : 0.7)))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
    }
}

/// An action inside a row, like Copy: clearly a button, but quieter than the footer's
/// white one, so each screen has a single obvious next step.
struct OnboardingChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverAware { hovering in
            configuration.label
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.08 : (hovering ? 0.2 : 0.13))))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
        }
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
    /// The tick's own size; the ring around it scales with it.
    var size: CGFloat = 16
    @State private var progress: CGFloat = 0

    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5 * size / 16, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .padding(6 * size / 16)
            // An empty ring until done, so an unfinished task reads as a checkbox
            // rather than a blank space.
            .background(Circle().fill(Color.green.opacity(progress > 0 ? 0.15 : 0)))
            .overlay(Circle().strokeBorder(Color.white.opacity(progress > 0 ? 0 : 0.3), lineWidth: 1.5 * size / 16))
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

/// A one-off burst of dots. Used twice: for the file landing on the shelf, which confirms
/// the single thing the tutorial asked for, and once as setup finishes. Runs for 0.7s
/// when `trigger` changes and costs nothing otherwise.
struct OnboardingBurst: View {
    let trigger: Int
    var radius: CGFloat = 46
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                let angle = Double(index) / 12 * 2 * .pi
                Circle()
                    .fill(index.isMultiple(of: 3) ? Color(hex: 0xB9A8FF) : .white)
                    .frame(width: 5, height: 5)
                    .offset(x: fired ? cos(angle) * radius : 0, y: fired ? sin(angle) * radius : 0)
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
