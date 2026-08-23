//
//  ClipboardSearchBar.swift
//  boringNotch
//

import SwiftUI

/// The search row.
///
/// Not a `TextField`: the notch window cannot become key, so no control inside it can
/// ever hold focus. The text and caret are drawn manually and driven entirely by
/// `ClipboardKeyCaptureService`, which avoids the "field looks focused but is dead"
/// failure mode.
///
/// It is always visible rather than appearing on first keystroke — otherwise there is
/// nothing on screen telling you that typing does anything at all.
struct ClipboardSearchBar: View {
    enum State: Equatable {
        /// Ready for typing.
        case ready
        /// A password field somewhere has enabled secure input, so taps see nothing.
        case secureInput
        /// Accessibility is not granted, so there is no key capture at all.
        case unavailable
    }

    let query: String
    let matchCount: Int
    let state: State

    static let height: CGFloat = 22

    @SwiftUI.State private var caretVisible = true

    private var caret: some View {
        Rectangle()
            .fill(Color.effectiveAccent)
            .frame(width: 1.5, height: 12)
            .opacity(caretVisible ? 1 : 0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(state == .ready ? .gray : Color.orange.opacity(0.9))

            switch state {
            case .ready:
                HStack(spacing: 1) {
                    // The caret goes before the placeholder and after typed text, which
                    // is where a real text field puts it: at the insertion point. Drawing
                    // it after the placeholder left it stranded at the far right of the
                    // hint, pointing at nothing.
                    if query.isEmpty {
                        caret
                        Text("Type to search")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .padding(.leading, 3)
                    } else {
                        Text(query)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        caret
                    }
                }
                if query.isEmpty {
                    Spacer(minLength: 6)
                    Text("⌥↩ plain text")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize()
                }
            case .secureInput:
                Text("Typing is unavailable while a password field is focused")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            case .unavailable:
                Text("Allow Accessibility in Settings to search and paste")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if !query.isEmpty {
                Text("\(matchCount)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.08))
        }
        .task(id: state) {
            guard state == .ready else { return }
            // Blink the caret so the row reads as an active input.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                caretVisible.toggle()
            }
        }
    }

    private var icon: String {
        switch state {
        case .ready: return "magnifyingglass"
        case .secureInput: return "lock.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }
}
