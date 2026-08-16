//
//  ClipboardEmptyStateView.swift
//  boringNotch
//

import SwiftUI

/// Shown before anything has been copied. Mirrors the Shelf's empty state so the two
/// tabs feel like the same app.
struct ClipboardEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)
            Text("Copy something to get started")
                .foregroundStyle(.gray)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
