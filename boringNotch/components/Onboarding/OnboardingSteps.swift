//
//  OnboardingSteps.swift
//  NotchFun
//

import AVFoundation
import Combine
import Defaults
import EventKit
import LaunchAtLogin
import SwiftUI

// MARK: - Hello

struct HelloStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            OnboardingStepHeader(
                title: "Hi. I live in your notch.",
                subtitle: "NotchFun turns the notch into a small, quiet place for what's playing, files you're moving around, what you've copied, and more."
            )

            VStack(alignment: .leading, spacing: 12) {
                hint("arrow.up", "Look at the top of your screen: the notch is the app.")
                hint("slider.horizontal.3", "Pick what it does, and it changes as you choose.")
                hint("clock", "About a minute. Everything can be changed later in Settings.")
            }
            .padding(.top, 6)
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Features

struct FeaturesStep: View {
    @Binding var hudChoice: Bool
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    @Default(.boringShelf) private var shelf
    @Default(.clipboardHistoryEnabled) private var clipboard
    @Default(.caffeineButtonInNotch) private var caffeine
    @Default(.showCalendar) private var calendar
    @Default(.showMirror) private var mirror
    @Default(.showAccessoryBattery) private var accessoryBattery

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "What should your notch do?",
                subtitle: "Changes apply straight away, so look up at the notch as you choose."
            )

            LazyVGrid(columns: columns, spacing: 10) {
                FeatureCard(icon: "music.note", title: "Now playing",
                            detail: "Artwork and controls for whatever's playing.",
                            isOn: $coordinator.musicLiveActivityEnabled)
                FeatureCard(icon: "tray.fill", title: "Shelf",
                            detail: "Drop files on the notch to keep them handy.",
                            isOn: $shelf)
                FeatureCard(icon: "doc.on.clipboard", title: "Clipboard history",
                            detail: "What you copy, searchable, on this Mac.",
                            note: "Paste needs Accessibility",
                            isOn: $clipboard)
                FeatureCard(icon: "cup.and.saucer.fill", title: "Caffeine",
                            detail: "Keep the Mac awake with one click.",
                            isOn: $caffeine)
                FeatureCard(icon: "calendar", title: "Calendar",
                            detail: "Today's events and reminders.",
                            note: "Needs Calendar access",
                            isOn: $calendar)
                FeatureCard(icon: "web.camera", title: "Mirror",
                            detail: "A quick camera check before a call.",
                            note: "Needs Camera access",
                            isOn: $mirror)
                FeatureCard(icon: "airpods", title: "AirPods battery",
                            detail: "Battery level when they connect.",
                            isOn: $accessoryBattery)
                FeatureCard(icon: "speaker.wave.2.fill", title: "Volume & brightness",
                            detail: "In the notch, instead of the system popup.",
                            note: "Needs Accessibility",
                            isOn: $hudChoice)
            }
        }
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let detail: String
    var note: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 1 : 0.6))
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                // Said up front, on the card that causes it, rather than as a surprise
                // on the next screen.
                if isOn, let note {
                    Text(note)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(10)
        // One height for every card, so the two in a row line up; grid rows otherwise
        // size to the taller card and centre the shorter one.
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isOn ? 0.10 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(isOn ? 0.28 : 0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { isOn.toggle() }
        .animation(NotchMotion.control, value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Permissions

struct PermissionsStep: View {
    let permissions: [OnboardingPermission]
    let wantsHUD: Bool
    let wantsClipboard: Bool
    let onAccessibilityGranted: () -> Void

    enum Status { case granted, denied, notAsked }
    @State private var status: [OnboardingPermission: Status] = [:]
    /// What was already granted on the first check, so those ticks appear drawn rather
    /// than animating news that is not news.
    @State private var grantedAtStart: Set<OnboardingPermission>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "A few permissions",
                subtitle: "Only for what you switched on. Nothing leaves your Mac. Skipping is fine; those features just stay quiet until you allow them."
            )

            VStack(spacing: 10) {
                ForEach(permissions, id: \.self) { permission in
                    row(permission)
                }
            }
        }
        // Re-checked while this step is on screen only. Accessibility is granted in
        // System Settings, which posts nothing this app can observe directly; the
        // polling ends the moment the step goes away.
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func row(_ permission: OnboardingPermission) -> some View {
        let state = status[permission] ?? .notAsked
        return HStack(spacing: 12) {
            Image(systemName: icon(permission))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title(permission))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(reason(permission))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if state == .granted {
                DrawnCheckmark(granted: true, drawsInOnAppear: !(grantedAtStart?.contains(permission) ?? true))
            } else {
                Button(state == .denied ? "Open Settings" : "Allow") {
                    Task { await request(permission, denied: state == .denied) }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func icon(_ permission: OnboardingPermission) -> String {
        switch permission {
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .camera: return "web.camera"
        case .accessibility: return "hand.raised.fill"
        }
    }

    private func title(_ permission: OnboardingPermission) -> String {
        switch permission {
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .camera: return "Camera"
        case .accessibility: return "Accessibility"
        }
    }

    private func reason(_ permission: OnboardingPermission) -> String {
        switch permission {
        case .calendar: return "Shows today's events in the notch."
        case .reminders: return "Shows reminders next to them. Optional."
        case .camera: return "For the mirror preview. Nothing is recorded."
        case .accessibility:
            switch (wantsHUD, wantsClipboard) {
            case (true, true): return "For the volume and brightness popup, and to paste from clipboard history."
            case (true, false): return "For the volume and brightness popup."
            default: return "Lets clipboard history paste straight into other apps."
            }
        }
    }

    private func settingsPane(_ permission: OnboardingPermission) -> String {
        switch permission {
        case .calendar: return "Privacy_Calendars"
        case .reminders: return "Privacy_Reminders"
        case .camera: return "Privacy_Camera"
        case .accessibility: return "Privacy_Accessibility"
        }
    }

    @MainActor
    private func request(_ permission: OnboardingPermission, denied: Bool) async {
        if denied {
            // macOS only shows its own prompt once. After a "Don't Allow", the switch
            // lives in System Settings.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPane(permission))") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        switch permission {
        case .calendar:
            _ = try? await CalendarService().requestAccess(to: .event)
        case .reminders:
            _ = try? await CalendarService().requestAccess(to: .reminder)
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .accessibility:
            _ = await XPCHelperClient.shared.ensureAccessibilityAuthorizationStatus(promptIfNeeded: true)
        }
        await refresh()
    }

    @MainActor
    private func refresh() async {
        var next: [OnboardingPermission: Status] = [:]
        for permission in permissions {
            switch permission {
            case .calendar: next[permission] = eventKitStatus(.event)
            case .reminders: next[permission] = eventKitStatus(.reminder)
            case .camera:
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: next[permission] = .granted
                case .denied, .restricted: next[permission] = .denied
                default: next[permission] = .notAsked
                }
            case .accessibility:
                // The helper cannot tell "declined" from "not asked yet", so this never
                // reads as denied; "Allow" again just brings up the system prompt.
                let granted = await XPCHelperClient.shared.accessibilityAuthorizationStatus() == true
                next[permission] = granted ? .granted : .notAsked
            }
        }
        if grantedAtStart == nil {
            grantedAtStart = Set(next.filter { $0.value == .granted }.map(\.key))
        }
        let accessibilityJustGranted = status[.accessibility] != .granted && next[.accessibility] == .granted
        withAnimation(NotchMotion.control) { status = next }
        if accessibilityJustGranted { onAccessibilityGranted() }
    }

    private func eventKitStatus(_ type: EKEntityType) -> Status {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }
}

// MARK: - Preferences

struct PreferencesStep: View {
    @Default(.openNotchOnHover) private var opensOnHover
    @Default(.menubarIcon) private var menubarIcon
    @Default(.showOnAllDisplays) private var showOnAllDisplays

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "A few preferences",
                subtitle: "The ones worth deciding now. The rest are in Settings."
            )

            VStack(spacing: 10) {
                row("power", "Launch at login", "Recommended, so the notch is back after a restart.") {
                    LaunchAtLogin.Toggle { EmptyView() }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                row("cursorarrow.rays", "Open the notch", "Hovering is quicker; clicking avoids opening it by accident.") {
                    Picker("", selection: $opensOnHover) {
                        Text("On hover").tag(true)
                        Text("On click").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                row("menubar.rectangle", "Menu bar icon", "Quick access to settings and Caffeine.") {
                    Toggle("", isOn: $menubarIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                // Only asked when it means something.
                if NSScreen.screens.count > 1 {
                    row("display.2", "Every display", "Show a notch on external displays too.") {
                        Toggle("", isOn: $showOnAllDisplays)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: showOnAllDisplays) {
                                NotificationCenter.default.post(name: .showOnAllDisplaysChanged, object: nil)
                            }
                    }
                }
            }
        }
    }

    private func row<Control: View>(
        _ icon: String, _ title: String, _ detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Try it

struct TryItStep: View {
    let tasks: [OnboardingTask]
    let opensOnHover: Bool
    @ObservedObject var state: OnboardingTryIt

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "Try it",
                subtitle: "Everything here uses the real notch, set up the way you just chose."
            )

            VStack(spacing: 10) {
                ForEach(tasks, id: \.self) { task in
                    taskRow(task)
                }
            }
        }
        .onAppear { state.start() }
    }

    @ViewBuilder
    private func taskRow(_ task: OnboardingTask) -> some View {
        let done = state.done.contains(task)
        HStack(spacing: 12) {
            DrawnCheckmark(granted: done)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(task))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail(task, done: done))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            switch task {
            case .openNotch:
                EmptyView()
            case .dragToShelf:
                SampleFileTile(state: state)
            case .copyText:
                Button(done ? "Copied" : "Copy") { state.copySample() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(done)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func title(_ task: OnboardingTask) -> String {
        switch task {
        case .openNotch: return opensOnHover ? "Hover over the notch" : "Click the notch"
        case .dragToShelf: return "Drag this file up to the notch"
        case .copyText: return "Copy something"
        }
    }

    private func detail(_ task: OnboardingTask, done: Bool) -> String {
        switch task {
        case .openNotch:
            return done ? "That's the notch open." : "At the very top of your screen, in the middle."
        case .dragToShelf:
            return done ? "It's on the shelf. Drag it out again whenever you need it." : "Drop it on the shelf when the notch opens."
        case .copyText:
            return done ? "Open the notch's clipboard tab and it's there." : "It will turn up in your clipboard history."
        }
    }
}

/// The file to drag. A drag starting in this app's own window is invisible to the
/// drag detector - it uses global event monitors, which never see this app's events -
/// so the notch would not open by itself. Starting the drag opens it on the shelf.
private struct SampleFileTile: View {
    @ObservedObject var state: OnboardingTryIt

    var body: some View {
        ZStack {
            VStack(spacing: 3) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                Text("Hello.txt")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: 58, height: 52)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(state.done.contains(.dragToShelf) ? 0.04 : 0.12)))
            .onDrag {
                state.beginDrag()
                guard let url = state.sampleFileURL() else { return NSItemProvider() }
                return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
            }
            OnboardingBurst(trigger: state.burstCount)
        }
    }
}

/// Watches the real notch, shelf and clipboard for the "Try it" tasks, and removes what
/// they left behind when setup ends: the sample file from the shelf and disk, and the
/// sample text from clipboard history.
@MainActor
final class OnboardingTryIt: ObservableObject {
    @Published private(set) var done: Set<OnboardingTask> = []
    @Published private(set) var burstCount = 0

    static let sampleText = "Hello from NotchFun"
    private static let sampleFileName = "Hello.txt"

    private var cancellables = Set<AnyCancellable>()
    private var fileURL: URL?
    private var closeTask: Task<Void, Never>?

    func isComplete(_ tasks: [OnboardingTask]) -> Bool {
        tasks.allSatisfy(done.contains)
    }

    func start() {
        guard cancellables.isEmpty, let delegate = AppDelegate.shared else { return }

        let models = [delegate.vm] + Array(delegate.viewModels.values)
        Publishers.MergeMany(models.map { $0.$notchState })
            .filter { $0 == .open }
            .first()
            .sink { [weak self] _ in self?.mark(.openNotch) }
            .store(in: &cancellables)

        ShelfStateViewModel.shared.$items
            .sink { [weak self] items in
                guard let self else { return }
                if items.contains(where: { $0.fileURL?.lastPathComponent == Self.sampleFileName }) {
                    self.shelfReceivedSample()
                }
            }
            .store(in: &cancellables)

        // Not visibleItems: that list only updates while the clipboard tab is showing.
        NotificationCenter.default.publisher(for: .clipboardHistoryDidCapture)
            .sink { [weak self] _ in
                if ClipboardStateViewModel.shared.newestItem?.title == Self.sampleText {
                    self?.mark(.copyText)
                }
            }
            .store(in: &cancellables)
    }

    func sampleFileURL() -> URL? {
        if let fileURL { return fileURL }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.sampleFileName)
        let text = "This file came from NotchFun's setup. It's safe to delete.\n"
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        fileURL = url
        return url
    }

    func beginDrag() {
        NotchActions.openNotch(tab: .shelf, autoClose: false)
    }

    func copySample() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.sampleText, forType: .string)
    }

    private func shelfReceivedSample() {
        guard !done.contains(.dragToShelf) else { return }
        mark(.dragToShelf)
        burstCount += 1
        // Leave the notch open long enough to see the file sitting on the shelf.
        closeTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            NotchActions.closeNotch()
        }
    }

    private func mark(_ task: OnboardingTask) {
        guard !done.contains(task) else { return }
        withAnimation(NotchMotion.control) { _ = done.insert(task) }
    }

    func cleanUp() {
        closeTask?.cancel()
        cancellables.removeAll()
        let shelf = ShelfStateViewModel.shared
        for item in shelf.items where item.fileURL?.lastPathComponent == Self.sampleFileName {
            shelf.remove(item)
        }
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        let clipboard = ClipboardStateViewModel.shared
        for item in clipboard.items(withTitle: Self.sampleText) {
            clipboard.delete(id: item.id)
        }
    }
}

// MARK: - Done

struct DoneStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.green)

            OnboardingStepHeader(
                title: "Your notch is ready.",
                subtitle: "A few things worth knowing:"
            )

            VStack(alignment: .leading, spacing: 12) {
                tip("keyboard", "⇧⌘I opens the notch from the keyboard.")
                tip("square.stack.3d.up", "Its actions are in the Shortcuts app, for automations.")
                tip("gearshape", "Everything you chose, and a lot more, is in Settings.")
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
