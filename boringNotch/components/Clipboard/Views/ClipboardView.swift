//
//  ClipboardView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct ClipboardView: View {

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var clipboard = ClipboardStateViewModel.shared

    @Default(.clipboardCleanLinks) private var cleanLinks

    /// Keeps the notch open while the tab is in use. Released on every exit path.
    @State private var hold: NotchHoldToken?
    @State private var selectedID: UUID?

    /// Current search text. Driven entirely by `ClipboardKeyCaptureService`, since no
    /// control inside the notch can hold keyboard focus.
    @State private var query: String = ""
    @State private var secureInputActive = false
    @State private var keyboardActive = false
    @State private var idleTask: Task<Void, Never>?
    @State private var outsideClickMonitor: Any?
    /// Only keyboard-driven selection scrolls the list. Hover must not, or moving the
    /// pointer while scrolling yanks the view out from under the user.
    @State private var selectionViaKeyboard = false

    // Scroll haptics, mirroring BoringCalendar: a Bool toggled at each event site and
    // consumed by .sensoryFeedback.
    @State private var haptics: Bool = false
    @State private var topRowID: UUID?
    /// Suppresses the tick caused by our own programmatic scrolling.
    @State private var scrollingByProgram = false
    @State private var lastTickAt: CFAbsoluteTime = 0

    private var matches: [ClipboardSearchService.Match] {
        ClipboardSearchService.search(query, in: clipboard.visibleItems)
    }

    /// Clears the history from inside the notch.
    ///
    /// Deletion here is unrecoverable, so a single tap only arms it: the button becomes a
    /// labelled confirmation naming how many entries would go, and a second tap within a
    /// few seconds does it. Option-click skips the confirmation once you know the button.
    /// Pinned entries always survive - pinning is a deliberate act, and the count shown
    /// excludes them.
    @ViewBuilder
    private var clearHistoryControl: some View {
        ClearConfirmButton(
            count: clipboard.unpinnedCount,
            idleHelp: "Clear history — pinned entries are kept",
            confirmHelp: "Delete these entries",
            action: performClear
        )
    }

    private func performClear() {
        clipboard.clearUnpinned()
    }

    private var searchState: ClipboardSearchBar.State {
        if secureInputActive { return .secureInput }
        return keyboardActive ? .ready : .unavailable
    }

    var body: some View {
        let results = matches

        VStack(spacing: 4) {
            if !clipboard.visibleItems.isEmpty {
                HStack(spacing: 6) {
                    ClipboardSearchBar(
                        query: query,
                        matchCount: results.count,
                        state: searchState
                    )
                    clearHistoryControl
                }
            }

            if clipboard.visibleItems.isEmpty {
                ClipboardEmptyStateView()
            } else if results.isEmpty {
                Text("No matches")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(results)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onAppear(perform: activate)
        .onDisappear(perform: deactivate)
        .onChange(of: vm.notchState) { _, state in
            if state == .closed { deactivate() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        )) { _ in
            // The user moved on to another app; stop holding their notch open.
            deactivate()
            vm.close(force: true)
        }
    }

    private func list(_ results: [ClipboardSearchService.Match]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.item.id) { index, match in
                        ClipboardRowView(
                            item: match.item,
                            highlightRanges: match.ranges,
                            shortcutLabel: shortcutLabel(for: match.item, among: results, at: index),
                            isSelected: match.item.id == selectedID,
                            cleansLink: cleanLinks && URLCleaner.wouldClean(match.item.title)
                        )
                        .equatable()
                        .id(match.item.id)
                        .onTapGesture { select(match.item) }
                        .onHover { hovering in
                            guard hovering else { return }
                            selectionViaKeyboard = false
                            selectedID = match.item.id
                            restartIdleTimer()
                        }
                        .contextMenu { contextMenu(for: match.item) }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollPosition(id: $topRowID, anchor: .top)
            .onChange(of: topRowID) { old, new in
                handleScrollChange(from: old, to: new)
            }
            .onChange(of: selectedID) { _, id in
                // Hover changes the selection constantly while the user scrolls;
                // scrolling on every one of those fights the gesture and stutters.
                guard selectionViaKeyboard, let id else { return }
                scrollingByProgram = true
                withAnimation(NotchMotion.control) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onHover { hovering in
                vm.isHoveringScrollableContent = hovering
            }
            .mask {
                // Fades the partially visible row at the bottom so the cut-off reads as
                // "more below" rather than as a clipping bug. Same idea as the
                // calendar's horizontal edge fade.
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin") {
            clipboard.togglePin(id: item.id)
        }
        Button("Copy") { select(item) }
        if item.kind == .files {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(clipboard.fileURLs(of: item))
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            clipboard.delete(id: item.id)
        }
    }

    // MARK: - Activation

    /// How long the tab may sit untouched before it gives the notch back. Without this
    /// the hold token would keep the notch open indefinitely once the pointer leaves.
    ///
    /// Hovering a row counts as interaction and resets the countdown, so this only
    /// really runs once the pointer has left the notch.
    private static let idleTimeout: Duration = .seconds(5)

    private func activate() {
        hold = NotchHoldToken { [weak vm] in
            vm?.close(force: true)
        }
        installOutsideClickMonitor()
        clipboard.beginPresenting()
        query = ""
        selectedID = clipboard.visibleItems.first?.id
        secureInputActive = ClipboardKeyCaptureService.isSecureInputActive
        restartIdleTimer()

        keyboardActive = ClipboardKeyCaptureService.shared.start { event in
            handle(event)
        }
    }

    private func deactivate() {
        vm.isHoveringScrollableContent = false
        removeOutsideClickMonitor()
        idleTask?.cancel()
        idleTask = nil
        ClipboardKeyCaptureService.shared.stop()
        keyboardActive = false
        query = ""
        hold?.release()
        hold = nil
        clipboard.endPresenting()
    }

    /// Closes the moment the user clicks anywhere outside the notch.
    ///
    /// While this tab is open the keyboard tap is consuming keystrokes, so there has to
    /// be an immediate, obvious way out — waiting for the idle timeout would leave the
    /// user unable to type in the app they just clicked into. A *global* monitor only
    /// receives events destined for other applications (clicks on the notch itself are
    /// delivered locally), so anything seen here is by definition an outside click.
    /// Mouse monitors need no Accessibility grant.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            Task { @MainActor in
                deactivate()
                vm.close(force: true)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    /// Any interaction — typing, scrolling, hovering a row — resets the countdown.
    private func restartIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak vm] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            deactivate()
            vm?.close(force: true)
        }
    }

    // MARK: - Keyboard

    private func handle(_ event: ClipboardKeyEvent) {
        restartIdleTimer()
        let results = matches

        switch event {
        case .character(let text):
            query += text
            // Keep a valid selection: the previously selected row may be filtered out.
            let updated = ClipboardSearchService.search(query, in: clipboard.visibleItems)
            if !updated.contains(where: { $0.item.id == selectedID }) {
                selectedID = updated.first?.item.id
            }

        case .backspace:
            guard !query.isEmpty else { return }
            query.removeLast()

        case .deleteWord:
            query = query.split(separator: " ").dropLast().joined(separator: " ")

        case .clearSearch:
            query = ""

        case .moveUp:
            move(by: -1, in: results)

        case .moveDown:
            move(by: 1, in: results)

        case .moveToTop:
            selectionViaKeyboard = true
            selectedID = results.first?.item.id
            fireHaptic()

        case .moveToBottom:
            selectionViaKeyboard = true
            selectedID = results.last?.item.id
            fireHaptic()

        case .pageUp:
            move(by: -4, in: results)

        case .pageDown:
            move(by: 4, in: results)

        case .confirm:
            if let id = selectedID, let match = results.first(where: { $0.item.id == id }) {
                select(match.item)
            }

        case .confirmAsPlainText:
            if let id = selectedID, let match = results.first(where: { $0.item.id == id }) {
                select(match.item, asPlainText: true)
            }

        case .cancel:
            // Escape always exits. It is the escape hatch from a tab that is holding
            // onto the keyboard, so it must never take two presses to work. Use
            // Control-U or backspace to clear the query without leaving.
            deactivate()
            vm.close(force: true)

        case .quickSelect(let number):
            let unpinned = results.filter { !$0.item.isPinned }
            guard number <= unpinned.count else { return }
            select(unpinned[number - 1].item)
        }
    }

    private func move(by offset: Int, in results: [ClipboardSearchService.Match]) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.item.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), results.count - 1)
        guard next != current else { return }
        selectionViaKeyboard = true
        selectedID = results[next].item.id
        fireHaptic()
    }

    // MARK: - Actions

    /// Ordering matters: the notch must be gone *before* Command-V is posted, so the
    /// keystroke lands in the app the user was actually working in and the pasteboard
    /// write has settled first.
    private func select(_ item: ClipboardItem, asPlainText: Bool = false) {
        fireHaptic()
        deactivate()
        // Forced: the user made a deliberate choice, so the hold must not block it.
        vm.close(force: true)

        // Copy unconditionally and first, so the entry is on the pasteboard even if
        // the permission check is pending or refused — the user can then paste it
        // themselves. Degrading beats doing nothing.
        if asPlainText {
            clipboard.copyToPasteboardAsPlainText(item)
        } else {
            clipboard.copyToPasteboard(item)
        }

        guard Defaults[.clipboardPasteOnSelect] else { return }

        guard ClipboardPasteService.ensureAuthorized(promptIfNeeded: true) else { return }
        Task {
            // Let the close animation and the pasteboard write land first.
            try? await Task.sleep(for: .milliseconds(120))
            ClipboardPasteService.paste()
        }
    }

    /// Quick-select label: pinned entries show their pin character, the first nine
    /// unpinned entries show their Command-number shortcut.
    private func shortcutLabel(
        for item: ClipboardItem,
        among results: [ClipboardSearchService.Match],
        at index: Int
    ) -> String? {
        if let pin = item.pin { return "⌥\(pin.uppercased())" }
        let unpinnedIndex = results.prefix(index).filter { !$0.item.isPinned }.count
        guard unpinnedIndex < 9 else { return nil }
        return "⌘\(unpinnedIndex + 1)"
    }

    // MARK: - Scroll haptics

    private func handleScrollChange(from old: UUID?, to new: UUID?) {
        // Ignore the initial nil -> id assignment and our own programmatic scrolls,
        // otherwise every appearance and every arrow-key move double-ticks.
        guard !scrollingByProgram else {
            scrollingByProgram = false
            return
        }
        guard old != nil, new != nil, old != new else { return }
        restartIdleTimer()
        fireHaptic()
    }

    /// Rate-limited so a hard flick through a long history reads as discrete ticks
    /// rather than a continuous buzz. The calendar can skip this because it only ever
    /// scrolls a handful of slow-moving items.
    private func fireHaptic() {
        guard Defaults[.enableHaptics] else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastTickAt > 0.02 else { return }
        lastTickAt = now
        haptics.toggle()
    }
}
